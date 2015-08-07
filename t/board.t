use strict;
use warnings;

use Test::More tests => 4;
use Data::Dumper;

use Games::Catan::Board;

my $board = Games::Catan::Board->new();

is( $board->graph->vertices, 54, '54 total vertices' );
is( $board->graph->edges, 70, '70 total edges' );
ok( $board->graph->is_connected, 'connected graph' );
ok( $board->graph->is_edge_connected, 'no bridges' );

