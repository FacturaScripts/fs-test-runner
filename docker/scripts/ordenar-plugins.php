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
 * Ordena los plugins a instalar, con las dependencias antes que el plugin que las necesita.
 *
 * Lee la clave "require" del facturascripts.ini de cada plugin. Una dependencia que no esté entre
 * los plugins disponibles se avisa por STDERR (hay que añadir su ruta a plugins.txt).
 *
 * Uso: php ordenar-plugins.php <carpeta_con_los_plugins> Plugin1 Plugin2 ...
 * Salida: los nombres ordenados, separados por espacios.
 *
 * @author Esteban Sánchez Martínez <esteban@factura.city>
 */

$carpeta = rtrim($argv[1] ?? '', '/');
$pedidos = array_slice($argv, 2);

/** @var string[] $orden Plugins ya resueltos, en orden de instalación. */
$orden = [];

/**
 * Añade un plugin a la lista después de sus dependencias.
 *
 * @param string $nombre Nombre del plugin.
 * @param string $carpeta Carpeta donde están los plugins.
 * @param string[] $orden Lista de plugins resueltos (se modifica).
 * @param string[] $visitando Plugins en proceso, para evitar ciclos.
 */
function resolver(string $nombre, string $carpeta, array &$orden, array $visitando = []): void
{
    if (in_array($nombre, $orden, true) || in_array($nombre, $visitando, true)) {
        return;
    }

    $ini = "$carpeta/$nombre/facturascripts.ini";
    if (!is_file($ini)) {
        fwrite(STDERR, "AVISO: la dependencia '$nombre' no está en plugins.txt; añade su ruta o fallará la activación.\n");
        return;
    }

    $datos = parse_ini_file($ini);
    $requeridos = array_filter(array_map('trim', explode(',', (string)($datos['require'] ?? ''))));
    foreach ($requeridos as $dependencia) {
        resolver($dependencia, $carpeta, $orden, array_merge($visitando, [$nombre]));
    }

    $orden[] = $nombre;
}

foreach ($pedidos as $plugin) {
    resolver($plugin, $carpeta, $orden);
}

echo implode(' ', $orden);
