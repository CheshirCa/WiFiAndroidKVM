/*
 * Copyright (C) CheshirCa 2026
 * https://t.me/cheshircanest
 */
/* WiFi Android KVM native agent: authenticated TCP input and LAN discovery. */
/* The server binds to the local LAN; AUTH is required before input is accepted. */
#include <errno.h>
#include <fcntl.h>
#include <arpa/inet.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define DEFAULT_HOLD_SECONDS 10
#define DEFAULT_SERVER_PORT 5556
#define DISCOVERY_PORT 5557
#define MESSAGE_SIZE 8
#define MESSAGE_AUTH 0x7d
#define AUTH_TIMEOUT_SECONDS 5
#define TCP_KEEP_IDLE_SECONDS 5
#define TCP_KEEP_INTERVAL_SECONDS 2
#define TCP_KEEP_PROBE_COUNT 3
static const uint8_t AUTH_TOKEN[7] = { 'K', 'V', 'M', '2', '0', '2', '6' };

enum { MESSAGE_MOVE = 0x01, MESSAGE_BUTTON = 0x02, MESSAGE_WHEEL = 0x03,
       MESSAGE_KEY = 0x04,
       MESSAGE_PING = 0x7e, MESSAGE_DISCONNECT = 0x7f };
enum { MOUSE_BUTTON_LEFT = 1, MOUSE_BUTTON_RIGHT = 2, MOUSE_BUTTON_MIDDLE = 3 };

static volatile sig_atomic_t keep_running = 1;
static volatile sig_atomic_t server_fd_for_signal = -1;
static const char DISCOVERY_REQUEST[] = "WAKVM_DISCOVER_1";
static const char DISCOVERY_REPLY_PREFIX[] = "WAKVM_REPLY_1|";

static void stop_handler(int number)
{
    (void)number;
    keep_running = 0;
    /* shutdown wakes accept() without closing a descriptor from a signal handler. */
    if (server_fd_for_signal >= 0) shutdown((int)server_fd_for_signal, SHUT_RDWR);
}

/* Discovery is intentionally separate from TCP input.  Its fixed request does
   not contain the TCP authentication token and it only returns public LAN data. */
struct discovery_config { unsigned short tcp_port; };

static void *run_discovery_server(void *argument)
{
    int fd, reuse_address = 1;
    struct discovery_config *config = (struct discovery_config *)argument;
    struct pollfd poll_fd;
    struct sockaddr_in address, peer, local;
    socklen_t peer_length, local_length;
    char request[64], reply[160], model[64] = "Android";
    ssize_t count;
    FILE *property;
    fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) { perror("discovery socket"); return NULL; }
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse_address, sizeof(reuse_address));
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(DISCOVERY_PORT);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("discovery bind"); close(fd); return NULL;
    }
    property = popen("/system/bin/getprop ro.product.model", "r");
    if (property != NULL) {
        if (fgets(model, sizeof(model), property) != NULL) model[strcspn(model, "\r\n|")] = '\0';
        pclose(property);
    }
    while (keep_running) {
        poll_fd.fd = fd;
        poll_fd.events = POLLIN;
        poll_fd.revents = 0;
        count = poll(&poll_fd, 1, 500);
        if (count < 0) {
            if (errno == EINTR && keep_running) continue;
            if (keep_running) perror("discovery poll");
            break;
        }
        if (count == 0 || (poll_fd.revents & POLLIN) == 0) continue;
        peer_length = sizeof(peer);
        count = recvfrom(fd, request, sizeof(request) - 1, 0, (struct sockaddr *)&peer, &peer_length);
        if (count < 0) { if (errno == EINTR) continue; break; }
        request[count] = '\0';
        if ((size_t)count != sizeof(DISCOVERY_REQUEST) - 1 || strcmp(request, DISCOVERY_REQUEST) != 0) continue;
        /* A connected UDP socket identifies the address chosen for this peer. */
        if (connect(fd, (struct sockaddr *)&peer, sizeof(peer)) < 0) continue;
        local_length = sizeof(local);
        if (getsockname(fd, (struct sockaddr *)&local, &local_length) == 0) {
            snprintf(reply, sizeof(reply), "%s%s|%s|%u|1", DISCOVERY_REPLY_PREFIX, model,
                     inet_ntoa(local.sin_addr), config->tcp_port);
            send(fd, reply, strlen(reply), 0);
        }
        { /* AF_UNSPEC disconnects UDP so the next broadcast can come from any host. */
            struct sockaddr disconnect_address;
            memset(&disconnect_address, 0, sizeof(disconnect_address));
            disconnect_address.sa_family = AF_UNSPEC;
            connect(fd, &disconnect_address, sizeof(disconnect_address));
        }
    }
    close(fd);
    return NULL;
}

static int write_full(int fd, const void *buffer, size_t length)
{
    const uint8_t *bytes = (const uint8_t *)buffer;
    size_t written = 0;
    ssize_t count;
    struct pollfd poll_fd;
    while (written < length) {
        count = write(fd, bytes + written, length - written);
        if (count > 0) { written += (size_t)count; continue; }
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            poll_fd.fd = fd;
            poll_fd.events = POLLOUT;
            poll_fd.revents = 0;
            if (poll(&poll_fd, 1, 1000) > 0) continue;
            errno = EAGAIN;
        }
        perror("write input event");
        return -1;
    }
    return 0;
}

static int emit_event(int fd, unsigned short type, unsigned short code, int value)
{
    struct input_event event;
    memset(&event, 0, sizeof(event));
    event.type = type;
    event.code = code;
    event.value = value;
    return write_full(fd, &event, sizeof(event));
}

static int synchronize_events(int fd)
{
    return emit_event(fd, EV_SYN, SYN_REPORT, 0);
}

static int emit_test_pattern(int fd)
{
    /* Pauses make each relative movement observable on the tablet. */
    if (emit_event(fd, EV_REL, REL_X, 300) < 0 || synchronize_events(fd) < 0) return -1;
    sleep(2);
    if (emit_event(fd, EV_REL, REL_Y, 220) < 0 || synchronize_events(fd) < 0) return -1;
    sleep(2);
    if (emit_event(fd, EV_REL, REL_X, -300) < 0 ||
        emit_event(fd, EV_REL, REL_Y, -220) < 0 || synchronize_events(fd) < 0) return -1;
    return 0;
}

static int create_virtual_mouse(int right_button_is_back)
{
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    struct uinput_user_dev device;
    if (fd < 0) { perror("open /dev/uinput"); return -1; }

    /* This legacy interface is compatible with the tablet's Linux 3.4. */
    if (ioctl(fd, UI_SET_EVBIT, EV_REL) < 0 || ioctl(fd, UI_SET_RELBIT, REL_X) < 0 ||
        ioctl(fd, UI_SET_RELBIT, REL_Y) < 0 || ioctl(fd, UI_SET_RELBIT, REL_WHEEL) < 0 ||
        ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0 || ioctl(fd, UI_SET_KEYBIT, BTN_LEFT) < 0 ||
        ioctl(fd, UI_SET_KEYBIT, BTN_RIGHT) < 0 || ioctl(fd, UI_SET_KEYBIT, BTN_MIDDLE) < 0 ||
        (right_button_is_back && ioctl(fd, UI_SET_KEYBIT, KEY_BACK) < 0)) {
        perror("configure uinput device"); close(fd); return -1;
    }

    memset(&device, 0, sizeof(device));
    strncpy(device.name, "WiFiAndroidKVM mouse", sizeof(device.name) - 1);
    device.id.bustype = BUS_VIRTUAL;
    device.id.vendor = 0x1d6b;
    device.id.product = 0x0104;
    device.id.version = 1;
    if (write_full(fd, &device, sizeof(device)) < 0) {
        perror("write uinput device description"); close(fd); return -1;
    }
    if (ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("UI_DEV_CREATE"); close(fd); return -1;
    }
    return fd;
}

static int is_allowed_keyboard_key(unsigned short key)
{
    /* This is the exact evdev set emitted by the Windows scan-code mapper.
       In particular, exclude BTN_* and power-management keys. */
    if (key >= KEY_ESC && key <= KEY_F12) return 1;
    switch (key) {
    case KEY_KPENTER: case KEY_RIGHTCTRL: case KEY_KPSLASH: case KEY_RIGHTALT:
    case KEY_HOME: case KEY_UP: case KEY_PAGEUP: case KEY_LEFT: case KEY_RIGHT:
    case KEY_END: case KEY_DOWN: case KEY_PAGEDOWN: case KEY_INSERT: case KEY_DELETE:
    case KEY_LEFTMETA: case KEY_RIGHTMETA:
        return 1;
    default:
        return 0;
    }
}

static int create_virtual_keyboard(void)
{
    int fd, key;
    struct uinput_user_dev device;
    fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("open /dev/uinput keyboard"); return -1; }
    if (ioctl(fd, UI_SET_EVBIT, EV_KEY) < 0) { perror("configure keyboard events"); close(fd); return -1; }
    /* Only declare keyboard keys sent by this client. KEY_MAX also includes
       BTN_* values, which could make Android classify this as another device. */
    for (key = KEY_ESC; key < BTN_MISC; ++key) {
        if (!is_allowed_keyboard_key((unsigned short)key)) continue;
        if (ioctl(fd, UI_SET_KEYBIT, key) < 0) { perror("configure keyboard key"); close(fd); return -1; }
    }
    memset(&device, 0, sizeof(device));
    strncpy(device.name, "WiFiAndroidKVM keyboard", sizeof(device.name) - 1);
    device.id.bustype = BUS_VIRTUAL;
    /* SurfPad's Generic.kl maps several standard Linux key codes to its
       gesture actions. Reuse its installed USB keyboard keylayout, which
       maps the same evdev codes to normal Android keyboard keys. */
    device.id.vendor = 0x046d;
    device.id.product = 0xc532;
    device.id.version = 1;
    if (write_full(fd, &device, sizeof(device)) < 0 || ioctl(fd, UI_DEV_CREATE) < 0) {
        perror("create uinput keyboard"); close(fd); return -1;
    }
    return fd;
}

static void destroy_virtual_device(int fd)
{
    if (fd >= 0) {
        if (ioctl(fd, UI_DEV_DESTROY) < 0) perror("UI_DEV_DESTROY");
        close(fd);
    }
}

static int release_all_keys(int fd, uint8_t pressed[KEY_MAX + 1])
{
    int key, changed = 0;
    for (key = KEY_ESC; key <= KEY_MAX; ++key) {
        if (pressed[key] && is_allowed_keyboard_key((unsigned short)key)) {
            if (emit_event(fd, EV_KEY, (unsigned short)key, 0) < 0) return -1;
            pressed[key] = 0;
            changed = 1;
        }
    }
    return changed ? synchronize_events(fd) : 0;
}

static int release_all_buttons(int fd, int right_button_is_back)
{
    if (emit_event(fd, EV_KEY, BTN_LEFT, 0) < 0 ||
        (!right_button_is_back && emit_event(fd, EV_KEY, BTN_RIGHT, 0) < 0) ||
        emit_event(fd, EV_KEY, BTN_MIDDLE, 0) < 0 ||
        (right_button_is_back && emit_event(fd, EV_KEY, KEY_BACK, 0) < 0)) return -1;
    return synchronize_events(fd);
}

static unsigned short button_code(uint8_t button)
{
    if (button == MOUSE_BUTTON_LEFT) return BTN_LEFT;
    if (button == MOUSE_BUTTON_RIGHT) return BTN_RIGHT;
    if (button == MOUSE_BUTTON_MIDDLE) return BTN_MIDDLE;
    return 0;
}

static int16_t decode_le16(const uint8_t *bytes)
{
    return (int16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
}

/* Returns 0 for an accepted message, 1 for a requested disconnect, -1 on failure. */
static int handle_message(int mouse_fd, int keyboard_fd, uint8_t pressed_keys[KEY_MAX + 1], const uint8_t message[MESSAGE_SIZE], int right_button_is_back)
{
    unsigned short code;
    switch (message[0]) {
    case MESSAGE_MOVE:
        if (emit_event(mouse_fd, EV_REL, REL_X, decode_le16(&message[1])) < 0 ||
            emit_event(mouse_fd, EV_REL, REL_Y, decode_le16(&message[3])) < 0) return -1;
        return synchronize_events(mouse_fd);
    case MESSAGE_BUTTON:
        code = button_code(message[1]);
        if (code == 0 || message[2] > 1) { fprintf(stderr, "Ignoring invalid button message.\n"); return 0; }
        /* Android 4.4 launcher treats BTN_RIGHT like a primary click. In this
           compatibility mode the documented right-button packet becomes Back. */
        if (right_button_is_back && message[1] == MOUSE_BUTTON_RIGHT) code = KEY_BACK;
        if (emit_event(mouse_fd, EV_KEY, code, message[2]) < 0) return -1;
        return synchronize_events(mouse_fd);
    case MESSAGE_WHEEL:
        if (emit_event(mouse_fd, EV_REL, REL_WHEEL, decode_le16(&message[1])) < 0) return -1;
        return synchronize_events(mouse_fd);
    case MESSAGE_KEY:
        code = (unsigned short)((uint16_t)message[1] | ((uint16_t)message[2] << 8));
        if (!is_allowed_keyboard_key(code) || message[3] > 1) { fprintf(stderr, "Ignoring invalid key message.\n"); return 0; }
        if (emit_event(keyboard_fd, EV_KEY, code, message[3]) < 0) return -1;
        pressed_keys[code] = message[3];
        return synchronize_events(keyboard_fd);
    case MESSAGE_PING: return 0;
    case MESSAGE_DISCONNECT: return 1;
    default: fprintf(stderr, "Ignoring unknown message type: %u\n", message[0]); return 0;
    }
}

/* TCP is a stream, so keep reading until exactly one fixed-length message arrives. */
static int receive_message(int client_fd, uint8_t message[MESSAGE_SIZE])
{
    size_t received = 0;
    ssize_t count;
    while (received < MESSAGE_SIZE) {
        count = recv(client_fd, message + received, MESSAGE_SIZE - received, 0);
        if (count == 0) return 0;
        if (count < 0) {
            if (errno == EINTR && keep_running) continue;
            if (keep_running) perror("recv");
            return -1;
        }
        received += (size_t)count;
    }
    return 1;
}

static int create_network_server(unsigned short port)
{
    int fd, reuse_address = 1;
    struct sockaddr_in address;
    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse_address, sizeof(reuse_address)) < 0) {
        perror("setsockopt SO_REUSEADDR"); close(fd); return -1;
    }
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(port);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind 0.0.0.0"); close(fd); return -1;
    }
    if (listen(fd, 1) < 0) { perror("listen"); close(fd); return -1; }
    return fd;
}

static void configure_client_socket(int client_fd)
{
    int no_delay = 1, keep_alive = 1;
    if (setsockopt(client_fd, IPPROTO_TCP, TCP_NODELAY, &no_delay, sizeof(no_delay)) < 0) perror("setsockopt TCP_NODELAY");
    if (setsockopt(client_fd, SOL_SOCKET, SO_KEEPALIVE, &keep_alive, sizeof(keep_alive)) < 0) perror("setsockopt SO_KEEPALIVE");
#ifdef TCP_KEEPIDLE
    { int value = TCP_KEEP_IDLE_SECONDS; if (setsockopt(client_fd, IPPROTO_TCP, TCP_KEEPIDLE, &value, sizeof(value)) < 0) perror("setsockopt TCP_KEEPIDLE"); }
#endif
#ifdef TCP_KEEPINTVL
    { int value = TCP_KEEP_INTERVAL_SECONDS; if (setsockopt(client_fd, IPPROTO_TCP, TCP_KEEPINTVL, &value, sizeof(value)) < 0) perror("setsockopt TCP_KEEPINTVL"); }
#endif
#ifdef TCP_KEEPCNT
    { int value = TCP_KEEP_PROBE_COUNT; if (setsockopt(client_fd, IPPROTO_TCP, TCP_KEEPCNT, &value, sizeof(value)) < 0) perror("setsockopt TCP_KEEPCNT"); }
#endif
}

static int set_auth_timeout(int client_fd)
{
    struct timeval timeout;
    timeout.tv_sec = AUTH_TIMEOUT_SECONDS;
    timeout.tv_usec = 0;
    return setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
}

static void clear_receive_timeout(int client_fd)
{
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    if (setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) perror("clear SO_RCVTIMEO");
}

static int run_server(int mouse_fd, int keyboard_fd, unsigned short port, int right_button_is_back)
{
    int server_fd = create_network_server(port);
    pthread_t discovery_thread;
    struct discovery_config discovery_config;
    int client_fd, received, handled;
    uint8_t message[MESSAGE_SIZE];
    uint8_t pressed_keys[KEY_MAX + 1];
    if (server_fd < 0) return EXIT_FAILURE;
    server_fd_for_signal = server_fd;
    discovery_config.tcp_port = port;
    if (pthread_create(&discovery_thread, NULL, run_discovery_server, &discovery_config) != 0) {
        perror("pthread_create discovery"); server_fd_for_signal = -1; close(server_fd); return EXIT_FAILURE;
    }
    printf("Listening on 0.0.0.0:%u.\n", port);
    while (keep_running) {
        client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR && keep_running) continue;
            if (keep_running) perror("accept");
            break;
        }
        configure_client_socket(client_fd);
        if (set_auth_timeout(client_fd) < 0) perror("setsockopt SO_RCVTIMEO");
        if (receive_message(client_fd, message) <= 0 || message[0] != MESSAGE_AUTH || memcmp(&message[1], AUTH_TOKEN, sizeof(AUTH_TOKEN)) != 0) {
            fprintf(stderr, "Rejected unauthenticated client.\n");
            close(client_fd);
            continue;
        }
        printf("Authenticated client connected.\n");
        clear_receive_timeout(client_fd);
        memset(pressed_keys, 0, sizeof(pressed_keys));
        while (keep_running && (received = receive_message(client_fd, message)) > 0) {
            handled = handle_message(mouse_fd, keyboard_fd, pressed_keys, message, right_button_is_back);
            if (handled != 0) break;
        }
        release_all_buttons(mouse_fd, right_button_is_back);
        release_all_keys(keyboard_fd, pressed_keys);
        close(client_fd);
        printf("Client disconnected.\n");
    }
    server_fd_for_signal = -1;
    close(server_fd);
    pthread_join(discovery_thread, NULL);
    return EXIT_SUCCESS;
}

static int parse_integer(const char *text, int minimum, int maximum, int *result)
{
    char *end;
    long value;
    errno = 0; value = strtol(text, &end, 10);
    if (errno != 0 || *text == '\0' || *end != '\0' || value < minimum || value > maximum) return -1;
    *result = (int)value;
    return 0;
}

static void print_usage(const char *program_name)
{
    fprintf(stderr, "Usage:\n  %s --test [--hold seconds]\n  %s --server [--port port] [--right-button-back]\n", program_name, program_name);
}

int main(int argc, char *argv[])
{
    int mouse_fd, keyboard_fd, hold_seconds = DEFAULT_HOLD_SECONDS, port = DEFAULT_SERVER_PORT, exit_code, index;
    int test_mode = 0, hold_seen = 0, port_seen = 0;
    int right_button_is_back = 0;
    struct sigaction action;
    if (argc < 2 || (strcmp(argv[1], "--test") != 0 && strcmp(argv[1], "--server") != 0)) {
        print_usage(argv[0]); return EXIT_FAILURE;
    }
    test_mode = strcmp(argv[1], "--test") == 0;
    for (index = 2; index < argc; ++index) {
        if (test_mode && strcmp(argv[index], "--hold") == 0 && !hold_seen && index + 1 < argc) {
            if (parse_integer(argv[++index], 0, 3600, &hold_seconds) < 0) return EXIT_FAILURE;
            hold_seen = 1;
        } else if (!test_mode && strcmp(argv[index], "--port") == 0 && !port_seen && index + 1 < argc) {
            if (parse_integer(argv[++index], 1, 65535, &port) < 0) return EXIT_FAILURE;
            port_seen = 1;
        } else if (!test_mode && strcmp(argv[index], "--right-button-back") == 0 && !right_button_is_back) {
            right_button_is_back = 1;
        } else { print_usage(argv[0]); return EXIT_FAILURE; }
    }

    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, NULL) < 0 || sigaction(SIGTERM, &action, NULL) < 0) {
        perror("sigaction"); return EXIT_FAILURE;
    }
    mouse_fd = create_virtual_mouse(right_button_is_back);
    if (mouse_fd < 0) return EXIT_FAILURE;
    keyboard_fd = create_virtual_keyboard();
    if (keyboard_fd < 0) { destroy_virtual_device(mouse_fd); return EXIT_FAILURE; }
    sleep(1); /* Let Android enumerate the input device. */
    if (test_mode) {
        if (emit_test_pattern(mouse_fd) < 0) { destroy_virtual_device(keyboard_fd); destroy_virtual_device(mouse_fd); return EXIT_FAILURE; }
        printf("Virtual mouse created. Holding it for %d second(s).\n", hold_seconds);
        while (keep_running && hold_seconds-- > 0) sleep(1);
        exit_code = EXIT_SUCCESS;
    } else exit_code = run_server(mouse_fd, keyboard_fd, (unsigned short)port, right_button_is_back);
    release_all_buttons(mouse_fd, right_button_is_back);
    destroy_virtual_device(keyboard_fd);
    destroy_virtual_device(mouse_fd);
    return exit_code;
}


