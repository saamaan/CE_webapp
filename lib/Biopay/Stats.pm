package Biopay::Stats;
use Dancer ':syntax';
use Moose;
use Dancer::Plugin::CouchDB;
use JSON qw/encode_json/;
use DateTime;
use Biopay::Util qw/now_dt/;
use methods;

has 'fuel_sold_alltime' => (is => 'ro', isa => 'Num', lazy_build => 1); #SP TTP
has 'active_members'    => (is => 'ro', isa => 'Num', lazy_build => 1);

method _build_active_members    { view_single_result('members/active_count', @_) }
method _build_fuel_sold_alltime { view_single_result('txns/litres_by_member' ) }

method fuel_sales      { view_single_result('txns/fuel_sales', @_) }
method co2_reduction   { int($self->fuel_sold_alltime * 1.94) } #SP TTP
method fuel_for_member { view_single_result('txns/litres_by_member', @_) }

method litres_per_txn  { 
    my $period = shift; 
#SP, empty period caused errors
$period ||= "day";
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

    my $val_hash = $results->{rows}[0]{value}; 
    my @data;
    while (my ($key, $value) = each %$val_hash) {
        push @data, [$key, $value];
    }
    return encode_json(\@data);
}

method litres_per_day  { 
    my $period = shift; 
#SP, empty period caused errors
$period ||= "day";
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

    my $val_hash = $results->{rows}[0]{value}; 
    my @data;
    while (my ($key, $value) = each %$val_hash) {
        push @data, [$key, $value];
    }
    return encode_json(\@data);
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
    my @data = map { [$_->{key} * 1000, $total += $_->{value}]} @{$results->{rows}};
    return encode_json(\@data);
}

method taxes_paid      {
    sprintf '%.02f', 
        $self->fuel_sold_alltime * 0.24     # Motor Fuels Tax  #SP TTP
        + $self->fuel_sold_alltime * 0.0639 # Carbon Tax       #SP TTP
        + ($self->fuel_sales - $self->fuel_sales / 1.05)          # HST
}

#Used to get the actual emitted value, 
#when the result of a view is expected to be a single row,
#e.g. when there is a nice reduction defined to aggregate everything!
#At the time of writing this comment, 
#it is being used on active_count for members and total litres sold
#to a member, which are both numeric. Therefore the else hack makes sense!
sub view_single_result {
    my $result = view(@_);
    #SP: return zero if there are no members or no sold fuel
    #return int $result->{rows}[0]{value};
    if (defined $result->{rows}[0]{value}) { return int $result->{rows}[0]{value}; }
    else { return 0; }
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
    return { map { $_ => $self->$_ } qw/fuel_sold_alltime active_members/ };
}
