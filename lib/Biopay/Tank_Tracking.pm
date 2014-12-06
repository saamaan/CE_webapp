package Biopay::Tank_Tracking;
use strict;
use warnings;
use Moose;
use Dancer::Plugin::CouchDB;
use Dancer ':syntax';
use Try::Tiny;
use methods;

extends 'Biopay::Resource';

my @tank_tracking_fields = qw/_id _rev Type biodiesel_vol diesel_vol biodiesel_warn_vol diesel_warn_vol pump warning_sent/;

has 'pump' => (isa => 'Str', is => 'ro', required => 1);
has 'biodiesel_vol' => (isa => 'Num', is => 'rw', required => 1);
has 'diesel_vol' => (isa => 'Num', is => 'rw', required => 1);
has 'biodiesel_warn_vol' => (isa => 'Num', is => 'rw', required => 1);
has 'diesel_warn_vol' => (isa => 'Num', is => 'rw', required => 1);
has 'warning_sent' => (isa => 'Bool', is => 'rw', required => 1);

method as_hash {
	my $hash = {};
	map { $hash->{$_} = $self->$_ } @tank_tracking_fields;
	return $hash;
}

sub view_base { 'tank_tracking' }
sub By_location { shift->By_view('by_location', @_) }
sub All_critical { shift->All_for_view('/all_critical', @_) }
sub All_critical_unnotified { shift->All_for_view('/all_critical_unnotified', @_) }
sub All { shift->All_for_view('/all', @_) }

method update_all {
	($self->{diesel_vol}, $self->{biodiesel_vol}, $self->{diesel_warn_vol}, 
		$self->{biodiesel_warn_vol}) = (@_);
	$self->warning_sent(0);
}

method diesel_critical {
	return ( $self->{diesel_vol} < $self->{diesel_warn_vol} ) ? 1 : 0;
}

method biodiesel_critical {
	return ( $self->{biodiesel_vol} < $self->{biodiesel_warn_vol} ) ? 1 : 0;
}

method warning {
	if ( $self->diesel_critical() and $self->biodiesel_critical() ) {
		return 'Diesel and biodiesel';
	}
	elsif ( $self->diesel_critical() ) {
		return 'Diesel';
	}
	elsif ( $self->biodiesel_critical() ) {
		return 'Biodiesel';
	}
	else {
		return 'normal';
	}
}

