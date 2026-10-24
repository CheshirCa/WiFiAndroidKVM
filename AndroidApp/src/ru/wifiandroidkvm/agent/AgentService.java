/*
 * Copyright (C) CheshirCa 2026
 * https://t.me/cheshircanest
 */
package ru.wifiandroidkvm.agent;

import android.app.Notification;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.PowerManager;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class AgentService extends Service {
    public static final String ACTION_START = "ru.wifiandroidkvm.agent.START";
    public static final String ACTION_STOP = "ru.wifiandroidkvm.agent.STOP";
    public static final String ACTION_CHECK = "ru.wifiandroidkvm.agent.CHECK";
    public static final String ACTION_STATUS = "ru.wifiandroidkvm.agent.STATUS";
    public static final String EXTRA_STATE = "state";
    public static final String EXTRA_MESSAGE = "message";
    public static final String STATE_CHECKING = "checking";
    public static final String STATE_STOPPED = "stopped";
    public static final String STATE_RUNNING = "running";
    public static final String STATE_ERROR = "error";

    private static final int NOTIFICATION_ID = 5556;
    private static final String DEVICE_AGENT = "/data/local/tmp/wifi_android_kvm_agent";
    private static final String DEVICE_PID = "/data/local/tmp/wifi_android_kvm_agent.pid";

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Object processLock = new Object();
    private Process agentProcess;
    private PowerManager.WakeLock cpuLock;
    private WifiManager.WifiLock wifiLock;
    private volatile String currentState = STATE_STOPPED;
    private volatile String currentMessage = "Агент остановлен.";

    @Override
    public void onCreate() {
        super.onCreate();
        PowerManager power = (PowerManager) getSystemService(Context.POWER_SERVICE);
        cpuLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "WiFiAndroidKVM:agent");
        WifiManager wifi = (WifiManager) getSystemService(Context.WIFI_SERVICE);
        wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "WiFiAndroidKVM:agent");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_CHECK : intent.getAction();
        if (ACTION_START.equals(action)) {
            worker.submit(new Runnable() { @Override public void run() { startAgent(); } });
        } else if (ACTION_STOP.equals(action)) {
            worker.submit(new Runnable() { @Override public void run() { stopAgent(); } });
        } else {
            worker.submit(new Runnable() { @Override public void run() { validateConfiguration(); } });
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        stopAgent();
        worker.shutdownNow();
        super.onDestroy();
    }

    private void startAgent() {
        if (isAgentAlive()) {
            updateStatus(STATE_RUNNING, "Агент уже запущен: TCP 5556, поиск UDP 5557.");
            return;
        }
        updateStatus(STATE_CHECKING, "Проверка root и /dev/uinput…");
        String problem = configurationProblem();
        if (problem != null) {
            updateStatus(STATE_ERROR, problem);
            return;
        }
        try {
            updateStatus(STATE_CHECKING, "Установка встроенного агента…");
            if (!installAgentBinary()) {
                updateStatus(STATE_ERROR, "Не удалось подготовить агент с root-правами. Подробности: install.log.");
                return;
            }
            updateStatus(STATE_CHECKING, "Запуск TCP-агента…");
            acquireLocks();
            postForegroundNotification();
            String command = "sh -c 'echo $$ > " + DEVICE_PID + "; exec " + DEVICE_AGENT
                    + " --server' >/data/local/tmp/wifi_android_kvm_agent.log 2>&1 & echo started";
            String started = runRoot(command, 3000);
            if (started == null || started.indexOf("started") < 0) {
                releaseLocks();
                updateStatus(STATE_ERROR, "Не удалось передать команду запуска root-службе.");
                return;
            }
            Thread.sleep(700);
            if (!isAgentAlive()) {
                releaseLocks();
                updateStatus(STATE_ERROR, "Агент завершился сразу после запуска. Проверьте разрешение su и /dev/uinput.");
                return;
            }
            updateStatus(STATE_RUNNING, "Агент работает: TCP 5556, поиск UDP 5557. Правая кнопка — обычная кнопка мыши для RDP.");
        } catch (Exception error) {
            releaseLocks();
            updateStatus(STATE_ERROR, "Не удалось запустить агент: " + error.getMessage());
        }
    }

    private void stopAgent() {
        updateStatus(STATE_CHECKING, "Остановка агента…");
        String stopCommand = "if [ -r " + DEVICE_PID + " ]; then p=$(cat " + DEVICE_PID
                + "); kill -TERM $p 2>/dev/null; i=0; while kill -0 $p 2>/dev/null && [ $i -lt 5 ]; do sleep 1; i=$((i+1)); done; "
                + "kill -KILL $p 2>/dev/null; rm -f " + DEVICE_PID + "; fi";
        runRoot(stopCommand, 8000);
        synchronized (processLock) {
            if (agentProcess != null) {
                agentProcess.destroy();
                agentProcess = null;
            }
        }
        releaseLocks();
        stopForeground(true);
        updateStatus(STATE_STOPPED, "Агент остановлен.");
        stopSelf();
    }

    private void validateConfiguration() {
        if (isAgentAlive()) {
            updateStatus(STATE_RUNNING, "Агент работает: TCP 5556, поиск UDP 5557. Правая кнопка — обычная кнопка мыши для RDP.");
            return;
        }
        updateStatus(STATE_CHECKING, "Проверка конфигурации…");
        String problem = configurationProblem();
        updateStatus(problem == null ? STATE_STOPPED : STATE_ERROR,
                problem == null ? "Готово: root и /dev/uinput доступны. Агент остановлен." : problem);
    }

    private String configurationProblem() {
        if (Build.VERSION.SDK_INT < 19) return "Требуется Android API 19 или новее.";
        if (Build.CPU_ABI == null || !Build.CPU_ABI.contains("armeabi")) return "Требуется ARMv7-совместимое устройство.";
        String identity = runRoot("id", 3000);
        if (identity == null || identity.indexOf("uid=0") < 0) return "Root недоступен: выдайте приложению разрешение su.";
        String uinput = runRoot("test -w /dev/uinput && echo ok", 3000);
        if (uinput == null || uinput.indexOf("ok") < 0) return "Root не может открыть /dev/uinput для записи.";
        return null;
    }

    private boolean installAgentBinary() throws IOException {
        File stagedAgent = new File(getFilesDir(), "wifi_android_kvm_agent");
        InputStream input = getResources().openRawResource(R.raw.wifi_android_kvm_agent);
        FileOutputStream output = new FileOutputStream(stagedAgent, false);
        byte[] buffer = new byte[8192];
        try {
            int count;
            while ((count = input.read(buffer)) > 0) output.write(buffer, 0, count);
            output.flush();
        } finally {
            input.close();
            output.close();
        }
        String command = "cp " + stagedAgent.getAbsolutePath() + " " + DEVICE_AGENT
                + " && chmod 755 " + DEVICE_AGENT + " && test -x " + DEVICE_AGENT + " && echo ok";
        String result = runRoot(command, 3000);
        return result != null && result.indexOf("ok") >= 0;
    }
    private boolean isAgentAlive() {
        synchronized (processLock) {
            if (agentProcess != null) {
                try {
                    agentProcess.exitValue();
                    agentProcess = null;
                } catch (IllegalThreadStateException stillRunning) {
                    return true;
                }
            }
        }
        String state = runRoot("if [ -r " + DEVICE_PID + " ] && kill -0 $(cat " + DEVICE_PID + ") 2>/dev/null; then echo alive; fi", 2000);
        return state != null && state.indexOf("alive") >= 0;
    }

    private String runRoot(String command, long timeoutMs) {
        Process process = null;
        try {
            process = new ProcessBuilder("su", "-c", command).redirectErrorStream(true).start();
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder output = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) output.append(line).append('\n');
            long deadline = System.currentTimeMillis() + timeoutMs;
            while (true) {
                try {
                    process.exitValue();
                    break;
                } catch (IllegalThreadStateException stillRunning) {
                    if (System.currentTimeMillis() >= deadline) {
                        process.destroy();
                        return null;
                    }
                    Thread.sleep(25);
                }
            }
            return process.exitValue() == 0 ? output.toString() : null;
        } catch (Exception ignored) {
            return null;
        } finally {
            if (process != null) process.destroy();
        }
    }

    private void acquireLocks() {
        // На SURFpad 4M Binder-вызовы Wi-Fi и PowerManager блокируются.
        // Постоянное foreground-уведомление остаётся механизмом сохранения службы.
    }

    private void releaseLocks() {
        if (wifiLock.isHeld()) wifiLock.release();
        if (cpuLock.isHeld()) cpuLock.release();
    }

    private void postForegroundNotification() {
        new Handler(getMainLooper()).post(new Runnable() {
            @Override public void run() { showNotification(); }
        });
    }
    private void showNotification() {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent pending = PendingIntent.getActivity(this, 0, open, PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification = new Notification.Builder(this)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(getString(R.string.notification_title))
                .setContentText(getString(R.string.notification_text))
                .setContentIntent(pending)
                .setOngoing(true)
                .build();
        startForeground(NOTIFICATION_ID, notification);
    }

    private void updateStatus(String state, String message) {
        currentState = state;
        currentMessage = message;
        Intent update = new Intent(ACTION_STATUS);
        update.setPackage(getPackageName());
        update.putExtra(EXTRA_STATE, state);
        update.putExtra(EXTRA_MESSAGE, message);
        sendBroadcast(update);
    }
}









