#!/usr/bin/perl

use Modern::Perl;
use SQLWrapper;

my $sql = SQLWrapper->new();
$sql->list();
$sql->show();