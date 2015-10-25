package Games::Catan::Player::Stupid;

use Moo;

with( 'Games::Catan::Player' );

use Data::Dumper;

### public methods ###

sub take_turn {

    my ( $self ) = @_;

    # keep track whether we've already played a development card
    my $played_dev_card = 0;

    # before we bother rolling, see if we've won the game
    my $score = $self->get_score();

    # we already won the game
    if ( $score >= 10 ) {

	$self->logger->info( $self->color . " claims victory!" );
	$self->game->winner( $self );
	return;
    }

    # see if we have any unplayed development cards
    my $development_cards = $self->development_cards;
    my @unplayed_development_cards;

    foreach my $development_card ( @$development_cards ) {

	# not a playable card
	next if !$development_card->playable;

	# already played this card
	next if $development_card->played;

	push( @unplayed_development_cards, $development_card );
    }

    # at least one unplayed dev card
    if ( @unplayed_development_cards > 0 ) {

	# randomly decide if we want to play one or not before we roll
	if ( int( rand( 2 ) ) ) {

	    $self->_play_random_development_card( @unplayed_development_cards );
	    $played_dev_card = 1;

	    # its possible we've won the game now
	    return if $self->game->winner;
	}
    }

    # player must now roll
    $self->game->roll( $self );

    #
    # TODO: trading
    #

    # decide again if we want to play a development card (if we haven't already)
    if ( !$played_dev_card && @unplayed_development_cards > 0 ) {
	
	if ( int( rand( 2 ) ) ) {

	    $self->_play_random_development_card( @unplayed_development_cards );
	    $played_dev_card = 1;

	    # its possible we've won the game now
	    return if $self->game->winner;
	}
    }

    # potentially build/buy stuff
    while ( 1 ) {

	my @buyable = ();	

	my $settlement_intersections;
	my $road_paths;

	if ( @{$self->roads} > 0 && $self->can_afford( $self->roads->[0] ) ) {

	    # also make sure there is somewhere on the board we can build one
	    $road_paths = $self->get_possible_road_paths();

	    push( @buyable, $self->roads->[0] ) if ( @$road_paths > 0 );
	}

	if ( @{$self->settlements} > 0 && $self->can_afford( $self->settlements->[0] ) ) {

	    # also make sure there is somewhere on the board we can build one
	    $settlement_intersections = $self->get_possible_settlement_intersections();

	    push( @buyable, $self->settlements->[0] ) if ( @$settlement_intersections > 0 );
	}

	if ( @{$self->cities} > 0 && $self->can_afford( $self->cities->[0] ) ) {

	    push( @buyable, $self->cities->[0] );
	}

	if ( @{$self->game->development_cards} > 0 && $self->can_afford( $self->game->development_cards->[0] ) ) {

	    push( @buyable, $self->game->development_cards->[0] );
	}

	# we cant afford anything!
	last if ( @buyable == 0 );	

	my $rand = int( rand( 2 ) );

	# randomly decide if we want to build anything or not
        last if $rand;

	# randomly choose something to build/buy
        my $num_items = @buyable;
	my $i = int( rand( $num_items ) );
        my $item = $buyable[$i];
	my $location;

	# are we upgrading a settlement to a city?
	if ( $item->isa( 'Games::Catan::Building::City' ) ) {

	    # randomly pick one of our played settlements to upgrade
	    my $graph = $self->game->board->graph;
	    my @vertices = $graph->vertices;
	    my @options;

	    foreach my $vertex ( @vertices ) {

		next if !$graph->has_vertex_attribute( $vertex, 'building' );

		my $building = $graph->get_vertex_attribute( $vertex, 'building' );

		next if !$building->isa( 'Games::Catan::Building::Settlement' );

		my $player = $building->player;

		next if ( $player->color ne $self->color );

		push( @options, $vertex );
	    }

	    my $num = @options;
	    my $i = int( rand( $num ) );
	    my $location = $options[$i];

	    $self->buy( $item, $location );
	}

	# are we building a new settlement?
	elsif ( $item->isa( 'Games::Catan::Building::Settlement' ) ) {

	    # randomly choose which intersection to build it at
	    my $num = @$settlement_intersections;
	    my $i = int( rand( $num ) );
	    my $intersection = $settlement_intersections->[$i];

	    $self->buy( $item, $intersection );
	}

	# are we building a new road?
	elsif ( $item->isa( 'Games::Catan::Road' ) ) {

            # randomly choose which path to build it at
            my $num = @$road_paths;
            my $i = int( rand( $num ) );
            my $path = $road_paths->[$i];

            $self->buy( $item, $path );
	}

	# must be buying a development card
	else {

	    $self->buy( $item );
	}

	# have we won the game now?
	$score = $self->get_score();

	if ( $score >= 10 ) {

	    $self->logger->info( $self->color . " claims victory!" );
	    $self->game->winner( $self );
	    return;
	}
    }
}

sub place_first_settlement {
    
    my ( $self ) = @_;
    
    $self->_place_starting_settlement();
}

sub place_second_settlement {

    my ( $self ) = @_;

    $self->_place_starting_settlement();
}

sub activate_robber {

    my ( $self ) = @_;

    my $graph = $self->game->board->graph;
    my $tiles = $self->game->board->tiles;

    my $resource_cards = $self->get_resource_cards();

    # randomly pick a new tile to move the robber to
    my $num_tiles = @$tiles;
    my $i = int( rand( $num_tiles ) );
    my $tile = $tiles->[$i];

    # move robber to the new tile
    $self->game->board->move_robber( $tile );

    # are there other players with settlements at this tile to steal from?
    my $vertices = $tile->vertices;

    my @players_to_rob;

    foreach my $vertex ( @$vertices ) {

	next if !$graph->has_vertex_attribute( $vertex, 'building' );
	
	my $building = $graph->get_vertex_attribute( $vertex, 'building' );
	my $player = $building->player;

	# dont rob from ourself
	next if ( $player->color eq $self->color );

	# dont rob from them if they have no cards to steal
	next if ( @{$player->get_resource_cards} == 0 );

	push( @players_to_rob, $player );
    }

    # was there at least one player to rob from?
    if ( @players_to_rob > 0 ) {

	# randomly pick one of the players to rob from
	my $num_players = @players_to_rob;
	my $i = int( rand( $num_players ) );
	my $player = $players_to_rob[$i];

	# randomly pick one of their cards
	my $card = $player->steal_resource_card();

	# its our card now!
	if ( $card->isa( 'Games::Catan::ResourceCard::Brick' ) ) {

	    push( @{$self->brick}, $card );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Lumber' ) ) {

	    push( @{$self->lumber}, $card );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Wool' ) ) {

	    push( @{$self->wool}, $card );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Grain' ) ) {

	    push( @{$self->grain}, $card );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Ore' ) ) {

	    push( @{$self->ore}, $card );
	}
    }
}

sub discard_robber_cards {

    my ( $self ) = @_;

    my $resource_cards = $self->get_resource_cards();

    # how many cards do we need to remove? (must be half, rounded down)
    my $num = int( @$resource_cards / 2 );

    my $cards = [];
    
    for ( my $i = 0; $i < $num; $i++ ) {
	
        # randomly pick one of our cards to remove
        my $num_cards = @$resource_cards;
        my $j = int( rand( $num_cards ) );
	my $card = splice( @$resource_cards, $j, 1 );

	push( @$cards, $card );	
    }

    my @removed;

    foreach my $card ( @$cards ) {

	if ( $card->isa( 'Games::Catan::ResourceCard::Brick' ) ) {

	    push( @removed, shift( @{$self->brick} ) );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Lumber' ) ) {

	    push( @removed, shift( @{$self->lumber} ) );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Wool' ) ) {

	    push( @removed, shift( @{$self->wool} ) );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Grain' ) ) {

	    push( @removed, shift( @{$self->grain} ) );
	}

	elsif ( $card->isa( 'Games::Catan::ResourceCard::Ore' ) ) {

	    push( @removed, shift( @{$self->ore} ) );
	}
    }

    $self->game->bank->give_resource_cards( \@removed );
}

### helper methods ###

sub _place_starting_settlement {

    my ( $self ) = @_;

    my $graph = $self->game->board->graph;

    # keep trying until we find a valid location
    FIND_INTERSECTION:
    
    my $intersection = $graph->random_vertex;

    # this intersection is already occupied!
    goto FIND_INTERSECTION if $graph->has_vertex_attribute( $intersection, "building" );
    
    # make sure we don't violate the distance rule
    my @neighbors = $graph->neighbors( $intersection );
    
    foreach my $neighbor ( @neighbors ) {
	
	goto FIND_INTERSECTION if $graph->has_vertex_attribute( $neighbor, "building" );
    }
    
    # place settlement on intersection
    my $settlement = shift( @{$self->settlements} );       
    $graph->set_vertex_attribute( $intersection, "building", $settlement );

    my @paths = $graph->edges_at( $intersection );

    foreach my $path ( @paths ) {

	my ( $int1, $int2 ) = @$path;

	# already a road built on this path
	next if $graph->has_edge_attribute( $int1, $int2, "road" );

	# take one of our roads and place it on the board
	my $road = shift( @{$self->roads} );
	$graph->set_edge_attribute( $int1, $int2, "road", $road );
    }
}

sub _play_random_development_card {

    my ( $self, @cards ) = @_;

    # grab a random development card to play
    my $i = int( rand( @cards ) );
    my $dev_card = $cards[$i];

    $dev_card->play();
}

1;
