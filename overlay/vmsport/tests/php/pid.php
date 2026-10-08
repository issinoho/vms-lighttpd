<?php
header('Content-Type: text/plain');
if (isset($_GET['sleep'])) usleep((int)$_GET['sleep'] * 1000);
echo getmypid(), "\n";
