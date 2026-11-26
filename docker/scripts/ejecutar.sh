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
# Script que se ejecuta DENTRO del contenedor de pruebas (lo lanza run-tests.sh).
#
# Subcomandos:
#   descargar-core [--actualizar]   Descarga el core de la rama master de GitHub (con sus tests) a la caché.
#   preparar-core <local|descarga>  Deja el core listo en /var/www/html (con PHPUnit instalado).
#   probar --db <motor> --plugins "A B" --pruebas "A" [--extras "A:Carpeta:X,A"] [--filtro X] [--core-tests]
#                                   En una copia de trabajo propia del motor (/opt/fs-run/<motor>),
#                                   recrea la BD, instala y activa los plugins y lanza los tests de
#                                   Test/main. Después, por cada carpeta extra (Test/<Carpeta> con
#                                   install-plugins.txt), otra pasada con solo los plugins de su lista.
#                                   Con --core-tests ejecuta la suite del propio core, sin plugins.
#
# Las carpetas /tmp/core-src y /tmp/plugins-src las rellena run-tests.sh con el código del usuario.
#
# @author Esteban Sánchez Martínez <esteban@factura.city>

set -u

# Carpeta de la instalación de FacturaScripts dentro del contenedor.
WEB=/var/www/html
# Caché compartida entre todos los contenedores (zip del core y caché de Composer).
CACHE=/cache
# Repositorio de GitHub del core.
REPO=NeoRazorX/facturascripts
# Rama del core que se prueba (la misma que usa el CI de GitHub de los plugins).
RAMA=master
# Copia de la carpeta Dinamic recién preparada, para empezar cada pasada de tests desde ella.
DINAMIC_LIMPIO=/opt/fs-dinamic-limpio
# Carpeta con una copia de trabajo del core por base de datos (los motores se prueban a la vez).
RUN=/opt/fs-run

# Descarga a la caché compartida el código fuente del último commit de la rama master del core.
# El zip se identifica por su commit: si master no ha cambiado se reutiliza; si hay commits nuevos,
# se descarga el nuevo y se borran los anteriores.
descargar_core() {
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/$REPO/commits/$RAMA" | php -r '$j = json_decode(stream_get_contents(STDIN), true); echo substr($j["sha"] ?? "", 0, 12);')
    if [ -z "$tag" ]; then
        echo "ERROR: no se ha podido averiguar el último commit de $RAMA (¿sin conexión o límite de GitHub?)." >&2
        return 1
    fi

    if [ "${1:-}" != "--actualizar" ] && [ -f "$CACHE/core-$tag.zip" ]; then
        echo "-> Core $RAMA ($tag) ya descargado."
    else
        echo "-> Descargando FacturaScripts $RAMA ($tag)..."
        curl -fsSL -o "$CACHE/core-$tag.zip.tmp" "https://github.com/$REPO/archive/$tag.zip" || return 1
        mv "$CACHE/core-$tag.zip.tmp" "$CACHE/core-$tag.zip"
        # quitamos los zips de commits anteriores para que la caché no crezca
        find "$CACHE" -maxdepth 1 -name 'core-*.zip' ! -name "core-$tag.zip" -delete
    fi
    echo "$tag" > "$CACHE/core-tag.txt"
}

# Instala las dependencias de Composer del core (incluido PHPUnit) si hacen falta.
instalar_dependencias_core() {
    if [ ! -f "$WEB/vendor/bin/phpunit" ]; then
        echo "-> Instalando dependencias del core con Composer (puede tardar unos minutos)..."
        (cd "$WEB" && composer install --no-interaction --prefer-dist --no-progress) || return 1
    fi
}

# Devuelve la carpeta Dinamic al estado del zip del core, sin restos de ejecuciones anteriores.
# FacturaScripts genera en Dinamic archivos de los plugins activados; si el plugin ya no está,
# esos archivos rompen la activación del siguiente. Así cada ejecución parte de una instalación limpia.
restaurar_dinamic() {
    local tag="$1"
    rm -rf /tmp/core-dinamic && mkdir -p /tmp/core-dinamic
    unzip -q "$CACHE/core-$tag.zip" '*/Dinamic/*' -d /tmp/core-dinamic || return 1
    rsync -a --delete /tmp/core-dinamic/*/Dinamic/ "$WEB/Dinamic/" || return 1
    rm -rf /tmp/core-dinamic
}

# Deja el core en /var/www/html: del código local copiado a /tmp/core-src o del zip descargado.
preparar_core() {
    mkdir -p "$WEB"
    if [ "${1:-}" = "local" ]; then
        # sincronizamos sin tocar lo propio de esta instalación (dependencias, plugins, datos y config);
        # Dinamic no viene del equipo (no se copia): se borra y FacturaScripts lo reconstruye al iniciarse
        # con los plugins que se prueban
        rsync -a --delete --exclude=/vendor --exclude=/node_modules --exclude=/Plugins --exclude=/MyFiles \
            --exclude=/config.php --exclude=/.fs-core /tmp/core-src/ "$WEB/" || return 1
        rm -rf "$WEB/Dinamic" && mkdir -p "$WEB/Dinamic"
        echo "local" > "$WEB/.fs-core"
    else
        local tag
        tag=$(cat "$CACHE/core-tag.txt" 2>/dev/null)
        if [ -z "$tag" ]; then
            echo "ERROR: el core no se ha descargado." >&2
            return 1
        fi

        if [ "$(cat "$WEB/.fs-core" 2>/dev/null)" != "$tag" ]; then
            echo "-> Instalando el core $tag en esta versión de PHP..."
            find "$WEB" -mindepth 1 -delete
            rm -rf /tmp/core-zip
            unzip -q "$CACHE/core-$tag.zip" -d /tmp/core-zip || return 1
            cp -a /tmp/core-zip/*/. "$WEB/" && rm -rf /tmp/core-zip
            echo "$tag" > "$WEB/.fs-core"
        else
            restaurar_dinamic "$tag" || return 1
        fi
    fi

    mkdir -p "$WEB/MyFiles" "$WEB/Plugins"
    instalar_dependencias_core || return 1

    # guardamos la carpeta Dinamic recién preparada para empezar cada pasada de tests desde ella
    mkdir -p "$DINAMIC_LIMPIO"
    rsync -a --delete "$WEB/Dinamic/" "$DINAMIC_LIMPIO/"
}

# Devuelve Dinamic al estado guardado al preparar el core. Entre pasadas cambian los plugins activos
# y los archivos que genera un plugin que ya no está romperían la activación de los siguientes.
limpiar_dinamic() {
    [ -d "$DINAMIC_LIMPIO" ] || return 0
    rsync -a --delete "$DINAMIC_LIMPIO/" "$PWD/Dinamic/"
}

# Ejecuta una pasada de tests: Dinamic limpio, solo los plugins indicados (con sus dependencias de
# Composer), base de datos vacía, plugins activados en orden y PHPUnit sobre cada carpeta de tests.
# $1 motor, $2 nombre de la BD, $3 plugins a instalar ("A B"), $4 filtro de PHPUnit (o vacío),
# resto: pares "Etiqueta=ruta/de/tests". Devuelve 0 si todo pasa, 1 si algún test falla y 2 si no
# se han podido instalar o activar los plugins.
pasada() {
    local motor="$1" nombre_bd="$2" plugins="$3" filtro="$4"
    shift 4

    limpiar_dinamic || return 2

    # plugins: solo los de esta pasada, con sus dependencias de Composer
    find Plugins -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    local p
    for p in $plugins; do
        rsync -a "/tmp/plugins-src/$p/" "Plugins/$p/" || return 2
        if [ -f "Plugins/$p/composer.json" ] && [ ! -d "Plugins/$p/vendor" ]; then
            echo "-> composer install de $p..."
            (cd "Plugins/$p" && composer install --no-dev --prefer-dist --no-interaction --no-progress) || return 2
        fi
    done

    # base de datos vacía y estado de la aplicación limpio
    php /opt/scripts/preparar-bd.php "$motor" "$nombre_bd" || return 2
    find MyFiles -mindepth 1 ! -name .gitignore -exec rm -rf {} + 2>/dev/null

    # activamos las dependencias y los plugins, en orden
    local orden
    orden=$(php /opt/scripts/ordenar-plugins.php /tmp/plugins-src $plugins) || return 2
    # shellcheck disable=SC2086
    php /opt/scripts/habilitar-plugins.php $orden || {
        echo "ERROR: no se han podido activar los plugins."
        return 2
    }

    # tests de cada carpeta pedida
    local codigo=0 par etiqueta ruta salida resumen c args
    for par in "$@"; do
        etiqueta="${par%%=*}"
        ruta="${par#*=}"
        echo "=== Tests de $etiqueta ==="
        # "@core" es la suite del propio core (phpunit.xml); lo demás, una carpeta de tests de plugin
        if [ "$ruta" = "@core" ]; then
            args=(-c phpunit.xml)
        else
            args=(-c phpunit-plugins.xml "$ruta")
        fi
        [ -n "$filtro" ] && args+=(--filter "$filtro")
        salida=$(php vendor/bin/phpunit "${args[@]}" 2>&1)
        c=$?
        echo "$salida"
        [ $c -ne 0 ] && codigo=1
        resumen=$(echo "$salida" | grep -E '^(OK \(|Tests: |No tests executed)' | tail -n 1)
        echo "RESUMEN[$etiqueta]: ${resumen:-sin resumen de PHPUnit}"
    done
    return $codigo
}

# Deja la copia de trabajo sin restos al acabar: sin plugins, sin datos en MyFiles y con Dinamic
# como al preparar el core. La limpieza al empezar cada pasada se mantiene por si una ejecución se
# corta a medias.
limpiar_al_terminar() {
    find Plugins -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
    find MyFiles -mindepth 1 ! -name .gitignore -exec rm -rf {} + 2>/dev/null
    limpiar_dinamic
}

# Ejecuta los tests de una base de datos: primero Test/main de los plugins pedidos (con todos los
# plugins de plugins.txt activados) y después, por cada carpeta extra, una pasada aparte con solo
# los plugins de su install-plugins.txt. Devuelve 0 si todo ha ido bien.
probar() {
    local motor="" plugins="" pruebas="" extras="" filtro="" core_tests=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --core-tests) core_tests=1; shift ;;
            --db) motor="$2"; shift 2 ;;
            --plugins) plugins="$2"; shift 2 ;;
            --pruebas) pruebas="$2"; shift 2 ;;
            --extras) extras="$2"; shift 2 ;;
            --filtro) filtro="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # copia de trabajo propia de esta base de datos, para poder probar todos los motores a la vez
    # en la misma versión de PHP (rsync solo copia lo que ha cambiado desde la vez anterior)
    local dir="$RUN/$motor"
    mkdir -p "$dir"
    rsync -a --delete --exclude=/Plugins/ --exclude=/MyFiles/ --exclude=/config.php "$WEB/" "$dir/" || return 1
    mkdir -p "$dir/Plugins" "$dir/MyFiles"
    cd "$dir" || return 1

    local nombre_bd
    nombre_bd="test$(php -r 'echo PHP_MAJOR_VERSION . PHP_MINOR_VERSION;')"

    local codigo=0 c p carpetas=()

    # tests del propio core: una sola pasada sin plugins
    if [ "$core_tests" -eq 1 ]; then
        pasada "$motor" "$nombre_bd" "" "$filtro" "Core=@core"
        c=$?
        limpiar_al_terminar
        [ $c -eq 2 ] && return 1
        return $c
    fi

    # pasada principal: Test/main de cada plugin con tests
    if [ -n "$pruebas" ]; then
        for p in $pruebas; do
            carpetas+=("$p=Plugins/$p/Test/main")
        done
        pasada "$motor" "$nombre_bd" "$plugins" "$filtro" "${carpetas[@]}"
        c=$?
        # si no se activan los plugins principales no tiene sentido seguir
        if [ $c -eq 2 ]; then
            limpiar_al_terminar
            return 1
        fi
        [ $c -ne 0 ] && codigo=1
    fi

    # pasadas extra: Test/<Carpeta> con solo los plugins de su install-plugins.txt
    local extra plugin carpeta lista
    for extra in $extras; do
        IFS=: read -r plugin carpeta lista <<< "$extra"
        pasada "$motor" "$nombre_bd" "${lista//,/ }" "$filtro" "$plugin/$carpeta=Plugins/$plugin/Test/$carpeta"
        c=$?
        if [ $c -eq 2 ]; then
            echo "RESUMEN[$plugin/$carpeta]: ERROR: no se han podido instalar o activar los plugins ${lista//,/, } (ver log)"
        fi
        [ $c -ne 0 ] && codigo=1
    done
    limpiar_al_terminar
    return $codigo
}

comando="${1:-}"
shift || true
case "$comando" in
    descargar-core) descargar_core "$@" ;;
    preparar-core) preparar_core "$@" ;;
    probar) probar "$@" ;;
    *)
        echo "Uso: ejecutar.sh descargar-core|preparar-core|probar" >&2
        exit 2
        ;;
esac
