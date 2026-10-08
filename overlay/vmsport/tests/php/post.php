<?php
header('Content-Type: application/json');
$f = [];
foreach ($_FILES as $n => $u)
    $f[$n] = ['name' => $u['name'], 'size' => $u['size'], 'error' => $u['error'],
              'md5' => $u['error'] === 0 ? md5_file($u['tmp_name']) : null];
$raw = file_get_contents('php://input');
echo json_encode(['post' => $_POST, 'files' => $f, 'rawlen' => strlen($raw)]), "\n";
