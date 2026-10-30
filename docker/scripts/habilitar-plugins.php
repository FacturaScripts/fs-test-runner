<?php
/**
 * This file is part of fs-test-runner for FacturaScripts
 * Copyright (C) 2026 Carlos García Gómez <carlos@facturascripts.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
/**
 * Activa en una instalación de FacturaScripts los plugins indicados como argumentos.
 *
 * Uso (desde la raíz de FacturaScripts): php /opt/scripts/habilitar-plugins.php Dependencia Plugin
 * Los plugins se activan en el orden recibido, así que las dependencias deben ir primero.
 * Código de salida: 0 si todo bien, 2 si algún plugin no se ha podido activar.
 */

use FacturaScripts\Core\Base\DataBase;
use FacturaScripts\Core\Cache;
use FacturaScripts\Core\Kernel;
use FacturaScripts\Core\Plugins;

define('FS_FOLDER', getcwd());

require_once FS_FOLDER . '/vendor/autoload.php';

$config = FS_FOLDER . '/config.php';
if (!file_exists($config)) {
    fwrite(STDERR, $config . " not found!\n");
    exit(2);
}

require_once $config;

// conectamos a la base de datos
$db = new DataBase();
$db->connect();

// limpiamos la caché
Cache::clear();

// iniciamos el kernel y los plugins
Kernel::init();
Plugins::init();

// activamos cada plugin recibido, en orden
foreach (array_slice($argv, 1) as $plugin) {
    if (Plugins::isEnabled($plugin)) {
        echo '-> Plugin ' . $plugin . ' ya activo.' . PHP_EOL;
        continue;
    }

    if (false === Plugins::enable($plugin)) {
        echo '-> Plugin ' . $plugin . ' NO se ha podido activar.' . PHP_EOL;
        $db->close();
        exit(2);
    }

    echo '-> Plugin ' . $plugin . ' activado.' . PHP_EOL;
}

$db->close();
