#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char executable[PATH_MAX];
    ssize_t length = readlink("/proc/self/exe", executable, sizeof(executable) - 1);
    if (length < 0) {
        fprintf(stderr, "Motiva Bricks: no se pudo localizar el ejecutable: %s\n", strerror(errno));
        return 1;
    }
    executable[length] = '\0';
    char *slash = strrchr(executable, '/');
    if (!slash) return 1;
    *slash = '\0';
    char script[PATH_MAX];
    if (snprintf(script, sizeof(script), "%s/JUGAR_MOTIVA_BRICKS.sh", executable) >= (int)sizeof(script)) {
        fprintf(stderr, "Motiva Bricks: ruta demasiado larga.\n");
        return 1;
    }
    execl("/bin/bash", "bash", script, (char *)NULL);
    fprintf(stderr, "Motiva Bricks: no se pudo iniciar %s: %s\n", script, strerror(errno));
    return 1;
}
