# Tests de plugins de FacturaScripts con Docker

Ejecuta los **tests unitarios de tus plugins** en **5 instalaciones limpias de FacturaScripts, una por
cada versión de PHP (8.1, 8.2, 8.3, 8.4 y 8.5)** y con MySQL y PostgreSQL, igual que el CI de GitHub.
No instalas PHP, Composer ni bases de datos: todo va en contenedores Docker.

## Arranque rápido

### Paso 1. Instala Docker y ábrelo

Instala [Docker](https://docs.docker.com/get-docker/) (en Windows y macOS, Docker Desktop) y déjalo
abierto. En **Windows** instala además [Git para Windows](https://git-scm.com/download/win), que trae
la terminal **Git Bash** que usaremos en el paso 3.

**Linux (Ubuntu, Debian, Kali...):** Docker Desktop no hace falta; instala Docker Engine. En la
terminal:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

Cierra sesión y vuelve a entrar (para que valga el grupo `docker`) y comprueba que funciona:

```bash
docker compose version
docker run --rm hello-world
```

Si el primer comando falla en tu distribución (por ejemplo en Kali), instala Docker y el plugin de Compose así:

```bash
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
```

y cierra sesión y vuelve a entrar.

### Paso 2. Escribe la ruta de tu plugin en `plugins.txt`

Abre el archivo `plugins.txt` (está en esta misma carpeta) con el Bloc de notas o cualquier editor y
escribe, en una línea, la ruta de la carpeta de tu plugin: la que contiene su `facturascripts.ini`.
Solo es **texto**: no tienes que abrir nada en esa carpeta. Por ejemplo, para probar el plugin Alquileres:

```
C:\ServBay\www\facturascripts\Plugins\Alquileres
```

Guarda el archivo. (Valen las barras `\` y las `/`.)

### Paso 3. Abre un terminal en la carpeta fs-test-runner

Es la carpeta que contiene este README, `plugins.txt` y `run-tests.sh`. **No** es la carpeta de tu plugin.

- **Windows (recomendado, Git Bash):** abre la carpeta `fs-test-runner` en el Explorador de archivos,
  haz clic derecho en un espacio vacío y elige **Open Git Bash here** (en Windows 11, primero
  "Mostrar más opciones"). Se abre una ventana negra: ya estás en la carpeta correcta.
- **Windows con WSL (Ubuntu):** abre la carpeta `fs-test-runner` en el Explorador, haz clic en la barra
  de direcciones, escribe `wsl` y pulsa Intro. Antes, en Docker Desktop activa
  **Settings → Resources → WSL integration** para tu Ubuntu y pulsa *Apply & restart*.
- **macOS / Linux:** abre la terminal y entra en la carpeta `fs-test-runner`, por ejemplo
  `cd ~/Descargas/fs-test-runner`.

Para comprobar que estás en el sitio correcto, escribe `ls`: debe aparecer `run-tests.sh` en la lista.
Entonces escribe:

```
bash run-tests.sh
```

La primera vez tarda varios minutos (construye las imágenes y descarga el core). Después, mucho menos.
Al final verás una tabla con el resultado de cada versión de PHP.

## 1. Indicar tus plugins (`plugins.txt`)

Escribe la ruta de la carpeta de cada plugin (la que contiene `facturascripts.ini`), una por línea:

| Sistema | Ejemplo |
|---|---|
| Linux | `/home/TuUsuario/plugins/MiPlugin` |
| macOS | `/Users/TuUsuario/plugins/MiPlugin` |
| Windows | `C:/Users/TuUsuario/plugins/MiPlugin` (con barras `/`; las `\` también valen) |

- Si tu plugin **depende de otros** (clave `require` de su `facturascripts.ini`), añade también sus
  rutas: se instalan y activan antes que el tuyo.
- Tus tests deben estar en la carpeta **`Test/main`** del plugin, como en el CI de los plugins de
  FacturaScripts. Un plugin sin esa carpeta se instala, pero no se prueba.
- Las líneas que empiezan por `#` son comentarios.

## 2. Leer el resultado

```
PHP   BD        Estado  Segundos Resumen
---   --        ------  -------- -------
8.1   mysql     OK      22       OK (83 tests, 287 assertions)
8.2   mysql     FALLO   14       Tests: 83, Assertions: 280, Failures: 1.
...
Combinaciones correctas: 9 de 10. Logs en: .../fs-test-runner/logs
```

| Estado | Significado |
|---|---|
| `OK` | Todos los tests pasan. |
| `FALLO` | Algún test falla. Mira el log para ver cuál. |
| `ERROR` | Ni siquiera se han podido ejecutar (no se activa el plugin, falla Composer...). Mira el log. |
| `SIN-TEST` | PHPUnit no ha encontrado ningún test (por ejemplo, un `--filter` que no coincide). |

Los **logs completos** están en la carpeta `logs/` (por ejemplo `logs/php8.3_mysql.log`). El código de
salida es `0` solo si todo está en `OK`, así que también sirve en integración continua.

## 3. Opciones

```bash
bash run-tests.sh --php 8.3              # solo PHP 8.3 (rápido, para el día a día)
bash run-tests.sh --php 8.1,8.5          # solo esas versiones
bash run-tests.sh --db postgres          # solo PostgreSQL (también: mysql, mariadb)
bash run-tests.sh --filter MiClaseTest   # solo una clase o método de test
bash run-tests.sh --core /ruta/a/core    # usa tu propio core en vez de descargar el estable
bash run-tests.sh --serial               # una versión de PHP detrás de otra (menos carga)
bash run-tests.sh --update-core          # vuelve a descargar la última versión estable del core
bash run-tests.sh --stop                 # detiene los contenedores
bash run-tests.sh --reset                # lo borra todo y empieza de cero
bash run-tests.sh --ayuda
```

Consejo: mientras desarrollas usa `--php 8.3 --db mysql` (unos 25 segundos) y antes de publicar
ejecuta `bash run-tests.sh` completo.

## Qué hace por dentro

1. Comprueba que Docker está en marcha y lee `plugins.txt`.
2. Arranca los contenedores: una instalación por versión de PHP y las bases de datos.
3. Descarga el core estable de GitHub (una sola vez) o usa el tuyo, e instala sus dependencias con
   Composer, incluido PHPUnit.
4. **Copia tus plugins** a cada contenedor (sin `.git` ni `node_modules`). Tus carpetas originales
   **nunca se modifican**.
5. Para cada base de datos: crea una **vacía**, activa tus plugins (dependencias primero) y ejecuta
   PHPUnit sobre `Plugins/<TuPlugin>/Test/main`.
6. Muestra la tabla de resultados.

Las versiones de PHP van en paralelo; las bases de datos de una misma versión, una tras otra. Las bases
de datos solo son accesibles desde los contenedores (no se publica ningún puerto), así que no chocan
con tu MySQL local. La carpeta `docker/` es la maquinaria (imagen, compose y scripts internos): no
hace falta tocarla.

## Problemas típicos

**`No such file or directory` al ejecutar `bash run-tests.sh`** — La terminal no está dentro de la carpeta
del proyecto. Ábrela desde esa carpeta (paso 3), o entra con `cd`. En WSL, las carpetas de Windows están en
`/mnt/c/...`; por ejemplo: `cd /mnt/c/Users/TuUsuario/Desktop/fs-test-runner`.

**`no encuentro Docker` en WSL** — En Docker Desktop: Settings → Resources → WSL integration, activa tu
Ubuntu y pulsa *Apply & restart*. Cierra y vuelve a abrir la terminal.

**`permission denied` al usar Docker en Linux** — Tu usuario no está en el grupo `docker`: ejecuta
`sudo usermod -aG docker $USER`, cierra sesión y vuelve a entrar.

**`Docker no responde`** — Abre Docker Desktop y espera a que indique que está en funcionamiento.
En Linux: `sudo systemctl start docker`.

**`Falta 'docker compose'`** — Tu Docker es antiguo; actualízalo (necesitas `docker compose` v2).

**En Windows: `\r: command not found` o `No such file or directory` al ejecutar el script** — El archivo
ha perdido los saltos de línea de Linux. Ejecuta `dos2unix run-tests.sh docker/scripts/*` o vuelve a
copiar la carpeta con `git config --global core.autocrlf input` activado.

**`la carpeta del plugin no existe` / `no es un plugin (falta facturascripts.ini)`** — Revisa
`plugins.txt`: la ruta debe ser la de la carpeta que contiene `facturascripts.ini`. En Windows usa
`C:/Users/...`.

**`plugins.txt no tiene ninguna ruta`** — Aún no has añadido ningún plugin.

**`ningún plugin de plugins.txt tiene la carpeta Test/main`** — Tus tests deben estar en `Test/main`
dentro del plugin.

**`no se ha podido descargar el core`** — Sin internet, o GitHub ha limitado las peticiones: espera unos
minutos y reintenta, o usa tu propio core con `--core`.

**`ERROR` con `no se han podido activar los plugins`** — Mira el log. Lo más habitual es una
dependencia que falta en `plugins.txt` (el script avisa con `AVISO: la dependencia 'X' no está en
plugins.txt`) o un `min_version`/`min_php` del plugin que no cumple la versión probada.

**Un test falla solo en una versión de PHP o base de datos** — Para eso sirve esto. Reprodúcelo solo
ahí: `bash run-tests.sh --php 8.1 --db postgres --filter MiClaseTest`, y mira el log.

**Va muy lento o el equipo se queda sin memoria** — Usa `--serial` o `--php 8.3`, y comprueba que Docker
tiene memoria suficiente (Docker Desktop → Settings → Resources; se recomiendan 4 GB o más).

**Algo se ha quedado a medias** — `bash run-tests.sh --reset` borra contenedores, bases de datos y caché;
la siguiente ejecución lo reconstruye todo.
