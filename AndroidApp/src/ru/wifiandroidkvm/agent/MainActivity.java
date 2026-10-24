/*
 * Copyright (C) CheshirCa 2026
 * https://t.me/cheshircanest
 */
package ru.wifiandroidkvm.agent;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private TextView statusView;
    private Button toggleButton;
    private boolean agentRunning;

    private final BroadcastReceiver statusReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            updateStatus(intent.getStringExtra(AgentService.EXTRA_STATE),
                    intent.getStringExtra(AgentService.EXTRA_MESSAGE));
        }
    };

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        statusView = (TextView) findViewById(R.id.status);
        toggleButton = (Button) findViewById(R.id.toggle);
        toggleButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                Intent command = new Intent(MainActivity.this, AgentService.class);
                command.setAction(agentRunning ? AgentService.ACTION_STOP : AgentService.ACTION_START);
                startService(command);
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        registerReceiver(statusReceiver, new IntentFilter(AgentService.ACTION_STATUS));
        Intent check = new Intent(this, AgentService.class);
        check.setAction(AgentService.ACTION_CHECK);
        startService(check);
    }

    @Override
    protected void onPause() {
        unregisterReceiver(statusReceiver);
        super.onPause();
    }

    private void updateStatus(String state, String message) {
        agentRunning = AgentService.STATE_RUNNING.equals(state);
        statusView.setText(message == null ? "Нет состояния агента." : message);
        toggleButton.setEnabled(!AgentService.STATE_CHECKING.equals(state));
        toggleButton.setText(agentRunning ? "Остановить агент" : "Запустить агент");
    }
}
