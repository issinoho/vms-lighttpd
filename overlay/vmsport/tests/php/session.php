<?php
session_start();
$_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
header('Content-Type: text/plain');
echo $_SESSION['n'], "\n";
