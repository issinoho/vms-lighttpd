<?php
// n bytes of a repeating pattern ("0123456789abcdef"), default 1 MB
$n = isset($_GET['n']) ? (int)$_GET['n'] : 1048576;
header('Content-Type: application/octet-stream');
$block = str_repeat('0123456789abcdef', 4096);   // 64 KB
for ($left = $n; $left > 0; $left -= strlen($block))
    echo $left >= strlen($block) ? $block : substr($block, 0, $left);
