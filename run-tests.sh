#!/usr/bin/env bash
# This file is part of fs-test-runner for FacturaScripts
# Copyright (C) 2026 Carlos García Gómez <carlos@facturascripts.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

#
# Lanza los tests unitarios de tus plugins de FacturaScripts en contenedores Docker
# (una instalación por versión de PHP, de la 8.1 a la 8.5) contra MySQL, PostgreSQL o MariaDB.
#
# Configuración: edita plugins.txt (rutas de tus plugins) y ejecuta ./run-tests.sh
# Uso:           ./run-tests.sh [opciones]       (ver ./run-tests.sh --ayuda)
#
# Funciona en Linux, macOS y Windows (con Git Bash o WSL). Solo necesita Docker.
#
# @author Esteban Sánchez Martínez <esteban@factura.city>

set -u

# En Git Bash (Windows) evita que se conviertan las rutas de Linux que se pasan a Docker.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

# Carpeta donde está este script; todo se ejecuta desde ella.
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$AQUI" || exit 1

# Valores por defecto (las opciones de la línea de comandos los sustituyen).
FS_CORE=""
PHP_VERSIONS="8.1 8.2 8.3 8.4 8.5"
DATABASES="mysql postgres"

FILTRO=""
SERIE=0
ACTUALIZAR_CORE=0
ACCION="probar"
LOGS="$AQUI/logs"

# Muestra la ayuda del script.
ayuda() {
    cat <<'AYUDA'
Uso: ./run-tests.sh [opciones]

  --php 8.3,8.4        Versiones de PHP a usar (8.1 a 8.5). Por defecto, las cinco.
  --db mysql,postgres  Bases de datos: mysql, postgres y/o mariadb. Por defecto, mysql y postgres.
  --core RUTA          Usa tu propio core de FacturaScripts en vez de descargar la última versión estable.
  --filter Nombre      Ejecuta solo una clase o método de test (--filter de PHPUnit).
  --serial             Ejecuta las versiones de PHP una detrás de otra en vez de en paralelo.
  --update-core        Vuelve a descargar la última versión estable del core.
  --stop               Detiene los contenedores (se conservan los datos).
  --reset              Borra contenedores, volúmenes y caché (empieza de cero).
  --ayuda              Muestra esta ayuda.

Las rutas de tus plugins se indican en plugins.txt.
AYUDA
}

# Escribe un mensaje de error y termina.
fallar() {
    echo "ERROR: $*" >&2
    exit 1
}

# Normaliza una ruta escrita por el usuario: barras /, ~ expandida y, en WSL, C:/... convertido a /mnt/c/...
normalizar_ruta() {
    local ruta="${1//\\//}"
    ruta="${ruta/#\~/$HOME}"
    ruta="${ruta%/}"
    if [[ "$ruta" =~ ^[A-Za-z]:/ ]] && command -v wslpath >/dev/null 2>&1; then
        ruta="$(wslpath -u "$ruta")"
    fi
    echo "$ruta"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --php) [ $# -ge 2 ] || fallar "--php necesita un valor"; PHP_VERSIONS="${2//,/ }"; shift 2 ;;
        --db) [ $# -ge 2 ] || fallar "--db necesita un valor"; DATABASES="${2//,/ }"; shift 2 ;;
        --core) [ $# -ge 2 ] || fallar "--core necesita un valor"; FS_CORE="$2"; shift 2 ;;
        --filter) [ $# -ge 2 ] || fallar "--filter necesita un valor"; FILTRO="$2"; shift 2 ;;
        --serial) SERIE=1; shift ;;
        --update-core) ACTUALIZAR_CORE=1; shift ;;
        --stop) ACCION="parar"; shift ;;
        --reset) ACCION="reset"; shift ;;
        --ayuda | --help | -h) ayuda; exit 0 ;;
        *) ayuda; fallar "opción desconocida: $1" ;;
    esac
done

# Ejecuta docker compose con el archivo de este proyecto (y el perfil de MariaDB, que es opcional).
dc() {
    docker compose -f docker/docker-compose.yml --profile mariadb "$@"
}

command -v docker >/dev/null 2>&1 || fallar "no encuentro Docker. Instálalo y ábrelo. Si usas WSL (Ubuntu en Windows): Docker Desktop > Settings > Resources > WSL integration, activa tu distribución y pulsa Apply & restart. Más detalles en el README."
docker info >/dev/null 2>&1 || fallar "Docker no responde. Abre Docker Desktop (o arranca el servicio) y reintenta. Si usas WSL (Ubuntu en Windows), activa tu distribución en Docker Desktop > Settings > Resources > WSL integration y pulsa Apply & restart."
docker compose version >/dev/null 2>&1 || fallar "Falta 'docker compose' (v2). Actualiza Docker."

case "$ACCION" in
    parar)
        dc stop
        exit $?
        ;;
    reset)
        printf 'Esto borra los contenedores, las bases de datos de pruebas y la caché. ¿Seguro? [s/N] '
        read -r respuesta
        [ "$respuesta" = "s" ] || [ "$respuesta" = "S" ] || exit 0
        dc down -v --remove-orphans
        exit $?
        ;;
esac

# --- validaciones ---------------------------------------------------------------------------------

for v in $PHP_VERSIONS; do
    case "$v" in
        8.1 | 8.2 | 8.3 | 8.4 | 8.5) ;;
        *) fallar "versión de PHP no soportada: $v (usa 8.1, 8.2, 8.3, 8.4 u 8.5)" ;;
    esac
done
for d in $DATABASES; do
    case "$d" in
        mysql | postgres | mariadb) ;;
        *) fallar "base de datos no soportada: $d (usa mysql, postgres o mariadb)" ;;
    esac
done

# Lee plugins.txt: una ruta por línea, sin líneas vacías ni comentarios (#).
RUTAS=()
NOMBRES=()
PRUEBAS=()
while IFS= read -r linea || [ -n "$linea" ]; do
    linea="${linea%$'\r'}"
    linea="${linea#"${linea%%[![:space:]]*}"}"
    linea="${linea%"${linea##*[![:space:]]}"}"
    case "$linea" in '' | '#'*) continue ;; esac
    linea="$(normalizar_ruta "$linea")"
    [ -d "$linea" ] || fallar "la carpeta del plugin no existe: $linea (revisa plugins.txt)"
    [ -f "$linea/facturascripts.ini" ] || fallar "no es un plugin (falta facturascripts.ini): $linea"
    RUTAS+=("$linea")
    NOMBRES+=("$(basename "$linea")")
    [ -d "$linea/Test/main" ] && PRUEBAS+=("$(basename "$linea")")
done < plugins.txt

[ ${#RUTAS[@]} -gt 0 ] || fallar "plugins.txt no tiene ninguna ruta. Añade la carpeta de tu plugin (mira el README)."
[ ${#PRUEBAS[@]} -gt 0 ] || fallar "ningún plugin de plugins.txt tiene la carpeta Test/main con tests."

if [ -n "$FS_CORE" ]; then
    FS_CORE="$(normalizar_ruta "$FS_CORE")"
    [ -f "$FS_CORE/Core/Kernel.php" ] || fallar "--core no apunta a un core de FacturaScripts: $FS_CORE"
fi

PLUGINS_TXT="${NOMBRES[*]}"
PRUEBAS_TXT="${PRUEBAS[*]}"
echo "Plugins: $PLUGINS_TXT"
echo "Con tests: $PRUEBAS_TXT"
echo "PHP: $PHP_VERSIONS | BD: $DATABASES"

# --- entorno Docker -------------------------------------------------------------------------------

# Nombre del servicio de una versión de PHP (8.3 -> test83).
servicio() {
    echo "test${1//./}"
}

SERVICIOS=""
PRIMER_SERVICIO=""
for v in $PHP_VERSIONS; do
    SERVICIOS="$SERVICIOS $(servicio "$v")"
    [ -n "$PRIMER_SERVICIO" ] || PRIMER_SERVICIO="$(servicio "$v")"
done
MOTORES="mysql postgres"
case " $DATABASES " in *" mariadb "*) MOTORES="$MOTORES mariadb" ;; esac

echo "Arrancando el entorno Docker (la primera vez construye las imágenes y tarda varios minutos)..."
# shellcheck disable=SC2086
dc up -d --build --wait $MOTORES $SERVICIOS || fallar "no se ha podido arrancar el entorno Docker."

mkdir -p "$LOGS"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ -z "$FS_CORE" ]; then
    ARGS_DESCARGA=()
    [ "$ACTUALIZAR_CORE" -eq 1 ] && ARGS_DESCARGA=(--actualizar)
    dc exec -T "$PRIMER_SERVICIO" bash /opt/scripts/ejecutar.sh descargar-core ${ARGS_DESCARGA[@]+"${ARGS_DESCARGA[@]}"} </dev/null \
        || fallar "no se ha podido descargar el core de FacturaScripts."
fi

# Copia una carpeta del equipo a otra dentro del contenedor (sin .git ni node_modules).
# $1 servicio, $2 carpeta local, $3 destino en el contenedor, $4... exclusiones extra de tar.
copiar() {
    local svc="$1" origen="$2" destino="$3"
    shift 3
    tar -C "$origen" --exclude=.git --exclude=.github --exclude=.idea --exclude=node_modules "$@" -cf - . \
        | dc exec -T "$svc" sh -c "mkdir -p '$destino' && tar -xf - -C '$destino'"
}

# Copia los plugins (y el core local, si lo hay) a un contenedor y deja el core listo con PHPUnit.
# $1 servicio. Devuelve 0 si todo ha ido bien.
preparar_version() {
    local svc="$1" i
    dc exec -T "$svc" sh -c 'rm -rf /tmp/plugins-src /tmp/core-src && mkdir -p /tmp/plugins-src /tmp/core-src' </dev/null || return 1
    for i in "${!RUTAS[@]}"; do
        copiar "$svc" "${RUTAS[$i]}" "/tmp/plugins-src/${NOMBRES[$i]}" || return 1
    done
    if [ -n "$FS_CORE" ]; then
        copiar "$svc" "$FS_CORE" /tmp/core-src --exclude=./vendor --exclude=./Plugins --exclude=./MyFiles --exclude=./config.php || return 1
        dc exec -T "$svc" bash /opt/scripts/ejecutar.sh preparar-core local </dev/null || return 1
    else
        dc exec -T "$svc" bash /opt/scripts/ejecutar.sh preparar-core descarga </dev/null || return 1
    fi
}

# Prepara una versión de PHP y ejecuta los tests en cada base de datos.
# Deja en $TMP/php<v>.txt una línea por base de datos: bd|estado|segundos|resumen
probar_version() {
    local v="$1" svc resultado log inicio estado resumen codigo
    svc="$(servicio "$v")"
    resultado="$TMP/php$v.txt"
    : > "$resultado"

    # copiamos plugins (y el core local, si lo hay) al contenedor y dejamos el core listo
    log="$LOGS/php${v}_preparacion.log"
    local db
    preparar_version "$svc" > "$log" 2>&1
    codigo=$?
    if [ $codigo -ne 0 ]; then
        for db in $DATABASES; do
            echo "$db|ERROR|0|no se ha podido preparar el core o los plugins (ver $log)" >> "$resultado"
        done
        return 0
    fi

    for db in $DATABASES; do
        log="$LOGS/php${v}_${db}.log"
        inicio=$SECONDS
        local extra=()
        [ -n "$FILTRO" ] && extra=(--filtro "$FILTRO")
        dc exec -T "$svc" bash /opt/scripts/ejecutar.sh probar --db "$db" --plugins "$PLUGINS_TXT" --pruebas "$PRUEBAS_TXT" \
            ${extra[@]+"${extra[@]}"} </dev/null > "$log" 2>&1
        codigo=$?

        resumen="$(grep '^RESUMEN\[' "$log" | sed -E 's/^RESUMEN\[([^]]*)\]: /\1: /' | paste -sd ';' - | sed 's/;/; /g')"
        if [ ${#PRUEBAS[@]} -eq 1 ]; then
            resumen="${resumen#*: }"
        fi
        if [ $codigo -eq 0 ] && echo "$resumen" | grep -q 'No tests executed'; then
            # PHPUnit sale con 0 aunque no encuentre tests (p. ej. un --filter que no coincide con nada)
            estado="SIN-TEST"
        elif [ $codigo -eq 0 ]; then
            estado="OK"
        elif grep -q '^RESUMEN\[' "$log"; then
            estado="FALLO"
        else
            estado="ERROR"
            resumen="$(grep -v '^[[:space:]]*$' "$log" | tail -n 1)"
        fi
        echo "$db|$estado|$((SECONDS - inicio))|${resumen:-sin resumen (ver log)}" >> "$resultado"
    done
}

# --- ejecución ------------------------------------------------------------------------------------

echo "Ejecutando los tests (los logs completos quedan en $LOGS)..."
PIDS=""
for v in $PHP_VERSIONS; do
    if [ "$SERIE" -eq 1 ]; then
        probar_version "$v"
    else
        probar_version "$v" &
        PIDS="$PIDS $!"
    fi
done
# shellcheck disable=SC2086
[ -z "$PIDS" ] || wait $PIDS

# --- resultado ------------------------------------------------------------------------------------

TOTAL=0
CORRECTAS=0
echo
printf '%-5s %-9s %-7s %-8s %s\n' "PHP" "BD" "Estado" "Segundos" "Resumen"
printf '%-5s %-9s %-7s %-8s %s\n' "---" "--" "------" "--------" "-------"
for v in $PHP_VERSIONS; do
    [ -f "$TMP/php$v.txt" ] || continue
    while IFS='|' read -r db estado segundos resumen; do
        [ -n "$db" ] || continue
        printf '%-5s %-9s %-7s %-8s %s\n' "$v" "$db" "$estado" "$segundos" "$resumen"
        TOTAL=$((TOTAL + 1))
        [ "$estado" = "OK" ] && CORRECTAS=$((CORRECTAS + 1))
    done < "$TMP/php$v.txt"
done
echo
echo "Combinaciones correctas: $CORRECTAS de $TOTAL. Logs en: $LOGS"

[ "$CORRECTAS" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]
