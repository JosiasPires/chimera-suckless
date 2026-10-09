#define _POSIX_C_SOURCE 200809L
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static int active = 1;
static int total = 5;
static int cpu = 0;
static int mem = 0;

static int get_cpu_usage(void)
{
    static long prev_total = 0, prev_idle = 0;
    FILE *f = fopen("/proc/stat", "r");
    if (!f)
        return 0;
    long user, nice, system, idle, iowait, irq, softirq, steal;
    fscanf(f, "cpu %ld %ld %ld %ld %ld %ld %ld %ld", &user, &nice, &system,
           &idle, &iowait, &irq, &softirq, &steal);
    fclose(f);
    long total = user + nice + system + idle + iowait + irq + softirq + steal;
    long total_diff = total - prev_total;
    long idle_diff = idle - prev_idle;
    prev_total = total;
    prev_idle = idle;
    if (total_diff == 0)
        return 0;
    return (int)(100 * (total_diff - idle_diff) / total_diff);
}

static int get_mem_usage(void)
{
    FILE *f = fopen("/proc/meminfo", "r");
    if (!f)
        return 0;
    long total = 0, available = 0;
    char key[64];
    long value;
    while (fscanf(f, "%63s %ld kB\n", key, &value) == 2) {
        if (strcmp(key, "MemTotal:") == 0)
            total = value;
        else if (strcmp(key, "MemAvailable:") == 0)
            available = value;
        if (total && available)
            break;
    }
    fclose(f);
    if (total == 0)
        return 0;
    return (int)((total - available) / 1024);
}

static int get_battery(void)
{
    const char *paths[] = {
        "/sys/class/power_supply/BAT0/capacity",
        "/sys/class/power_supply/BAT1/capacity",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        FILE *f = fopen(paths[i], "r");
        if (!f)
            continue;
        int cap = -1;
        fscanf(f, "%d", &cap);
        fclose(f);
        return cap;
    }
    return -1;
}

static void get_net(char *out, size_t outsz)
{
    DIR *d = opendir("/sys/class/net");
    if (!d) {
        snprintf(out, outsz, "net:n/a");
        return;
    }
    struct dirent *e;
    char best[64] = "";
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.')
            continue;
        if (strcmp(e->d_name, "lo") == 0)
            continue;
        char p[256];
        snprintf(p, sizeof(p), "/sys/class/net/%s/operstate", e->d_name);
        FILE *f = fopen(p, "r");
        if (!f)
            continue;
        char st[16] = "";
        fscanf(f, "%15s", st);
        fclose(f);
        if (strcmp(st, "up") == 0) {
            snprintf(best, sizeof(best), "%s:up", e->d_name);
            break;
        }
        if (best[0] == '\0')
            snprintf(best, sizeof(best), "%s:%s", e->d_name, st);
    }
    closedir(d);
    if (best[0] == '\0')
        snprintf(out, outsz, "net:down");
    else {
        snprintf(out, outsz, "%.60s", best);
    }
}

static void get_temp(char *out, size_t outsz)
{
    const char *zones[] = {
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/class/thermal/thermal_zone1/temp",
        "/sys/class/hwmon/hwmon0/temp1_input",
        "/sys/class/hwmon/hwmon1/temp1_input",
        "/sys/class/hwmon/hwmon2/temp1_input",
        NULL
    };
    for (int i = 0; zones[i]; i++) {
        FILE *f = fopen(zones[i], "r");
        if (!f)
            continue;
        long t = 0;
        fscanf(f, "%ld", &t);
        fclose(f);
        if (t > 1000)
            t = t / 1000;
        snprintf(out, outsz, "%ldC", t);
        return;
    }
    snprintf(out, outsz, "n/a");
}

static void spawn_ws(int fd[2])
{
    pid_t pid = fork();
    if (pid == 0) {
        dup2(fd[1], STDOUT_FILENO);
        close(fd[0]);
        close(fd[1]);
        execl("/usr/local/bin/bswcctl", "bswcctl", "sub", "ws", NULL);
        execlp("bswcctl", "bswcctl", "sub", "ws", NULL);
        _exit(1);
    }
}

static void render(void)
{
    char ws[512] = {0};
    for (int i = 1; i <= total && strlen(ws) < sizeof(ws) - 16; i++) {
        strcat(ws, (i == active) ? " [=] " : " [ ] ");
    }
    char dt[64];
    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    strftime(dt, sizeof(dt), "%Y-%m-%d %H:%M", tm);
    char net[64], temp[16];
    get_net(net, sizeof(net));
    get_temp(temp, sizeof(temp));
    int bat = get_battery();
    if (bat >= 0)
        printf("%%{l} %s %%{c}%s%%{r} %s %s %d%% %dMB BAT %d%% \n",
               dt, ws, net, temp, cpu, mem, bat);
    else
        printf("%%{l} %s %%{c}%s%%{r} %s %s %d%% %dMB \n",
               dt, ws, net, temp, cpu, mem);
    fflush(stdout);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    int fd[2];
    pipe(fd);
    spawn_ws(fd);
    close(fd[1]);
    FILE *ws = fdopen(fd[0], "r");
    fcntl(fd[0], F_SETFL, O_NONBLOCK);
    while (1) {
        fd_set set;
        FD_ZERO(&set);
        FD_SET(fileno(ws), &set);
        struct timeval tv = {0, 0};
        int r = select(fileno(ws) + 1, &set, NULL, NULL, &tv);
        if (r > 0 && FD_ISSET(fileno(ws), &set)) {
            char line[128];
            while (fgets(line, sizeof(line), ws)) {
                int a, tt;
                if (sscanf(line, "%*s %*s %d %d", &a, &tt) == 2) {
                    active = a;
                    total = tt;
                }
            }
        }
        cpu = get_cpu_usage();
        mem = get_mem_usage();
        render();
        nanosleep(&(struct timespec){0, 500000000L}, NULL);
    }
}
