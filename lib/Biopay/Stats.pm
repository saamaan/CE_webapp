package Biopay::Stats;
use Dancer ':syntax';
use Moose;
use Dancer::Plugin::CouchDB;
use JSON qw/encode_json/;
use DateTime;
use Biopay::Util qw/now_dt/;
use methods;

use Data::Dumper;

has 'fuel_sold_alltime' => (is => 'ro', isa => 'HashRef', lazy_build => 1);
has 'diesel_sold_alltime' => (is => 'ro', isa => 'Num', lazy_build => 1);
has 'biodiesel_sold_alltime' => (is => 'ro', isa => 'Num', lazy_build => 1);	#may not be necessary as a separate attrib, but added it anyway
has 'active_members' => (is => 'ro', isa => 'Num', lazy_build => 1);			#may not be necessary as a separate attrib, but added it anyway

method _build_active_members    { view_single_num('members/active_count', @_) }
method _build_diesel_sold_alltime { $self->fuel_sold_alltime->{litres_diesel} }
method _build_biodiesel_sold_alltime { $self->fuel_sold_alltime->{litres_biodiesel} }
method _build_fuel_sold_alltime {
		#DB might be empty at first or something else might go wrong..
		my $ret = view_single_obj('txns/litres_by_member' );
		unless ( exists $ret->{litres} && exists $ret->{litres_diesel} && exists $ret->{litres_biodiesel} ) {
			$ret = { litres_diesel => 0, litres_biodiesel => 0, litres => 0 };
		}

		return $ret;
}


method fuel_sales      { view_single_num('txns/fuel_sales', @_) }
method co2_reduction   { return int($self->fuel_sold_alltime->{litres_biodiesel} * 1.94) }
method fuel_for_member { view_single_obj('txns/litres_by_member', @_) }

#This delegates away and returns a json encodes hash (of json encoded plot data).
#Ajax updating graphs (on client side) will use this, hence the encoding of the hash. 
method litres_per_txn_json {
		return encode_json( $self->litres_per_txn(@_) );
}

#This delegates away and returns a json encodes hash (of json encoded plot data).
#Ajax updating graphs (on client side) will use this, hence the encoding of the hash. 
method litres_per_day_json {
		return encode_json( $self->litres_per_day(@_) );
}

#This returns a hash ref. The template will be rendered with this at the beginning,
#on server side, hence no json encoding of the hash.
method litres_per_txn  { 
	my $period = shift; 
#SP, empty period caused errors
$period ||= "alltime";
    my $opts = {};

    # DateTime::Duration expects plurals
    my %valid_periods = map { $_ => $_ . "s" } qw(day week month year);
    
    if (exists $valid_periods{$period}) {
        my $dt = now_dt();
# Uncomment to test, since we have no txns from recently 
# $dt = DateTime->from_epoch(epoch => 1310846160);
# $opts->{endkey} = [$dt->epoch()];
        if ($period eq 'week') {
            $dt->subtract( days => 7 );
        } else {
            $dt->subtract( $valid_periods{$period} => 1); 
        }
        $opts->{startkey} = [$dt->epoch()];
    }

    my $results = view('txns/litres_per_txn', $opts);

    # format data so flot can read it
	#SP
	# it requires array object of point - [x, y] - array objects
	# [[1, 2], [3, 4]]

    my $val_hash = $results->{rows}[0]{value};

    my @diesel;
    while (my ($key, $value) = each %{$val_hash->{diesel}}) {
        push @diesel, [$key, $value];
    }
	my @biodiesel;
    while (my ($key, $value) = each %{$val_hash->{biodiesel}}) {
        push @biodiesel, [$key, $value];
    }    
	
	my $data = {diesel => encode_json(\@diesel), biodiesel => encode_json(\@biodiesel) };
	return $data;
}

#This returns a hash ref. The template will be rendered with this at the beginning,
#on server side, hence no json encoding of the hash.
method litres_per_day  { 
    my $period = shift; 
#SP, empty period caused errors
$period ||= "alltime";
    my $opts = {};

    # DateTime::Duration expects plurals
    my %valid_periods = map { $_ => $_ . "s" } qw(day week month year);
    
    my $dt = now_dt();
# Uncomment to test, since we have no txns from recently 
# $dt = DateTime->from_epoch(epoch => 1310846160);
# $opts->{endkey} = [$dt->epoch()];
    if (exists $valid_periods{$period}) {
        if ($period eq 'week') {
            $dt->subtract( days => 7 );
        } else {
            $dt->subtract( $valid_periods{$period} => 1); 
        }
        $opts->{startkey} = [$dt->epoch()];
    }

    my $results = view('txns/litres_per_day', $opts);

    # format data so flot can read it
	#SP
	# it requires array object of point - [x, y] - array objects
	# [[1, 2], [3, 4]]

    my $val_hash = $results->{rows}[0]{value};

	my @diesel;
    while (my ($key, $value) = each %{$val_hash->{diesel}}) {
        push @diesel, [$key, $value];
    }
	my @biodiesel;
    while (my ($key, $value) = each %{$val_hash->{biodiesel}}) {
        push @biodiesel, [$key, $value];
    }

    my $data = {diesel => encode_json(\@diesel), biodiesel => encode_json(\@biodiesel)};
    return $data;
}

method cumulative_members {
    my $results = view('members/by_epoch');
    
    my $total = 0;
    my @data = map { [$_->{key} * 1000, $total++]} @{$results->{rows}};
    return encode_json(\@data);
}

method cumulative_litres {
    my $results = view('txns/litres_by_date', {group => 1});

    my $total = 0;
    my @diesel = map { [$_->{key} * 1000, $total += $_->{value}->{litres_diesel}]} @{$results->{rows}};
	$total = 0;
    my @biodiesel = map { [$_->{key} * 1000, $total += $_->{value}->{litres_biodiesel}]} @{$results->{rows}};

	my $data = { diesel => encode_json(\@diesel), biodiesel => encode_json(\@biodiesel) };
    return $data;
}

method taxes_paid      {
    sprintf '%.02f', 
        $self->fuel_sold_alltime->{litres} * 0.24     # Motor Fuels Tax  #SP TTP
        + $self->fuel_sold_alltime->{litres} * 0.1023 # Carbon Tax       #SP TTP
        + $self->fuel_sold_alltime->{litres} * 0.04   # Fuel excise tax
        + ($self->fuel_sales - $self->fuel_sales / 1.05)          # HST
}

#SP
#Used to get the actual emitted value, 
#when the result of a view is expected to be a single row with a single number,
#e.g. when there is a nice reduction defined to aggregate everything!
sub view_single_num {
    my $result = view(@_);
    #SP: return zero if there are no members or no sold fuel
    #return int $result->{rows}[0]{value};
	if (defined $result->{rows}[0]{value}) { return int $result->{rows}[0]{value}; }
    else { return 0; }
}

#SP
#Used to get the actual emitted value, 
#when the result of a view is expected to be a single row with a single object,
#e.g. when there is a nice reduction defined to aggregate everything!
sub view_single_obj {
    my $result = view(@_);
	return $result->{rows}[0]{value};
}

sub view {
    my ($view, @args) = @_;
    if (exists $args[0] and not ref($args[0])) {
        # Assume it's a key
        @args = ( { key => "$args[0]" } );
    }

    return couchdb->view($view, @args)->recv;
}

method as_hash {
    return { map { $_ => $self->$_ } qw/biodiesel_sold_alltime diesel_sold_alltime active_members/ };
}
