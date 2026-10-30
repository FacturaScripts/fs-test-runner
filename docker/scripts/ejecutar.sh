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
#   descargar-core [--actualizar]   Descarga la última versión estable del core (código fuente de GitHub) a la caché.
#   preparar-core <local|descarga>  Deja el core listo en /var/www/html (con PHPUnit instalado).
#   probar --db <motor> --plugins "A B" --pruebas "A" [--filtro X]
#                                   Recrea la BD, instala y activa los plugins y lanza sus tests.
#
# Las carpetas /tmp/core-src y /tmp/plugins-src las rellena run-tests.sh con el código del usuario.

set -u

# Carpeta de la instalación de FacturaScripts dentro del contenedor.
WEB=/var/www/html
# Caché compartida entre todos los contenedores (zip del core y caché de Composer).
CACHE=/cache
# Repositorio de GitHub del core.
REPO=NeoRazorX/facturascripts

# Descarga el código fuente de la última versión estable del core a la caché compartida.
descargar_core() {
    local tag
    tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | php -r '$j = json_decode(stream_get_contents(STDIN), true); echo $j["tag_name"] ?? "";')
    if [ -z "$tag" ]; then
        echo "ERROR: no se ha podido averiguar la última versión estable (¿sin conexión o límite de GitHub?)." >&2
        return 1
    fi

    if [ "${1:-}" != "--actualizar" ] && [ -f "$CACHE/core-$tag.zip" ]; then
        echo "-> Core $tag ya descargado."
    else
        echo "-> Descargando FacturaScripts $tag..."
        curl -fsSL -o "$CACHE/core-$tag.zip.tmp" "https://github.com/$REPO/archive/refs/tags/$tag.zip" || return 1
        mv "$CACHE/core-$tag.zip.tmp" "$CACHE/core-$tag.zip"
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

# Deja el core en /var/www/html: del código local copiado a /tmp/core-src o del zip descargado.
preparar_core() {
    mkdir -p "$WEB"
    if [ "${1:-}" = "local" ]; then
        # sincronizamos sin tocar lo propio de esta instalación (dependencias, plugins, datos y config)
        rsync -a --delete --exclude=/vendor --exclude=/node_modules --exclude=/Plugins --exclude=/MyFiles \
            --exclude=/config.php --exclude=/.fs-core /tmp/core-src/ "$WEB/" || return 1
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
        fi
    fi

    mkdir -p "$WEB/MyFiles" "$WEB/Plugins"
    instalar_dependencias_core
}

# Recrea la BD, copia y activa los plugins y ejecuta sus tests. Devuelve 0 si todo ha ido bien.
probar() {
    local motor="" plugins="" pruebas="" filtro=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --db) motor="$2"; shift 2 ;;
            --plugins) plugins="$2"; shift 2 ;;
            --pruebas) pruebas="$2"; shift 2 ;;
            --filtro) filtro="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    cd "$WEB" || return 1
    local nombre_bd
    nombre_bd="test$(php -r 'echo PHP_MAJOR_VERSION . PHP_MINOR_VERSION;')"

    # plugins: solo los de esta ejecución, con sus dependencias de Composer
    find Plugins -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    local p
    for p in $plugins; do
        rsync -a "/tmp/plugins-src/$p/" "Plugins/$p/" || return 1
        if [ -f "Plugins/$p/composer.json" ] && [ ! -d "Plugins/$p/vendor" ]; then
            echo "-> composer install de $p..."
            (cd "Plugins/$p" && composer install --no-dev --prefer-dist --no-interaction --no-progress) || return 1
        fi
    done

    # base de datos vacía y estado de la aplicación limpio
    php /opt/scripts/preparar-bd.php "$motor" "$nombre_bd" || return 1
    find MyFiles -mindepth 1 ! -name .gitignore -exec rm -rf {} + 2>/dev/null

    # activamos las dependencias y los plugins, en orden
    local orden
    orden=$(php /opt/scripts/ordenar-plugins.php /tmp/plugins-src $plugins) || return 1
    # shellcheck disable=SC2086
    php /opt/scripts/habilitar-plugins.php $orden || {
        echo "ERROR: no se han podido activar los plugins."
        return 1
    }

    # tests de cada plugin pedido
    local codigo=0 salida resumen c args
    for p in $pruebas; do
        echo "=== Tests de $p ==="
        args=(-c phpunit-plugins.xml)
        [ -n "$filtro" ] && args+=(--filter "$filtro")
        salida=$(php vendor/bin/phpunit "${args[@]}" "Plugins/$p/Test/main" 2>&1)
        c=$?
        echo "$salida"
        [ $c -ne 0 ] && codigo=$c
        resumen=$(echo "$salida" | grep -E '^(OK \(|Tests: |No tests executed)' | tail -n 1)
        echo "RESUMEN[$p]: ${resumen:-sin resumen de PHPUnit}"
    done
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
