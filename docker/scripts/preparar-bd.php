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
 * Prepara la base de datos de una instalación de pruebas de FacturaScripts.
 *
 * Recrea una base de datos vacía en el motor indicado y escribe el config.php de la instalación.
 *
 * Uso (desde la raíz de FacturaScripts): php /opt/scripts/preparar-bd.php <mysql|mariadb|postgres> <nombre_bd>
 * Código de salida: 0 si todo bien, 2 si falla algo.
 *
 * @author Esteban Sánchez Martínez <esteban@factura.city>
 */

/** @var array<string, array{tipo: string, host: string, puerto: int}> Datos de conexión de cada motor. */
$motores = [
    'mysql' => ['tipo' => 'mysql', 'host' => 'mysql', 'puerto' => 3306],
    'mariadb' => ['tipo' => 'mysql', 'host' => 'mariadb', 'puerto' => 3306],
    'postgres' => ['tipo' => 'postgresql', 'host' => 'postgres', 'puerto' => 5432],
];

$motor = $argv[1] ?? '';
$nombre = $argv[2] ?? '';
if (!isset($motores[$motor]) || !preg_match('/^[a-z0-9_]+$/', $nombre)) {
    fwrite(STDERR, "Uso: php preparar-bd.php <mysql|mariadb|postgres> <nombre_bd>\n");
    exit(2);
}

$datos = $motores[$motor];
$usuario = 'root';
$clave = 'root';

try {
    // nos conectamos al servidor, sin base de datos concreta, para recrearla
    if ($motor === 'postgres') {
        $pdo = new PDO("pgsql:host={$datos['host']};port={$datos['puerto']};dbname=postgres", $usuario, $clave);
        $pdo->exec("DROP DATABASE IF EXISTS $nombre WITH (FORCE)");
        $pdo->exec("CREATE DATABASE $nombre");
    } else {
        $pdo = new PDO("mysql:host={$datos['host']};port={$datos['puerto']}", $usuario, $clave);
        $pdo->exec("DROP DATABASE IF EXISTS $nombre");
        $pdo->exec("CREATE DATABASE $nombre CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci");
    }
} catch (PDOException $e) {
    fwrite(STDERR, 'No se ha podido recrear la base de datos ' . $nombre . ': ' . $e->getMessage() . "\n");
    exit(2);
}

$config = <<<PHP
<?php
define('FS_COOKIES_EXPIRE', 31536000);
define('FS_ROUTE', '');
define('FS_DB_TYPE', '{$datos['tipo']}');
define('FS_DB_HOST', '{$datos['host']}');
define('FS_DB_PORT', {$datos['puerto']});
define('FS_DB_NAME', '$nombre');
define('FS_DB_USER', '$usuario');
define('FS_DB_PASS', '$clave');
define('FS_DB_FOREIGN_KEYS', true);
define('FS_DB_TYPE_CHECK', true);
define('FS_MYSQL_CHARSET', 'utf8mb4');
define('FS_MYSQL_COLLATE', 'utf8mb4_unicode_520_ci');
define('FS_LANG', 'es_ES');
define('FS_TIMEZONE', 'Europe/Madrid');
define('FS_HIDDEN_PLUGINS', '');
define('FS_DEBUG', true);
define('FS_DISABLE_ADD_PLUGINS', false);
define('FS_DISABLE_RM_PLUGINS', false);

PHP;

file_put_contents(getcwd() . '/config.php', $config);
echo "-> Base de datos $nombre ($motor) recreada y config.php escrito.\n";
