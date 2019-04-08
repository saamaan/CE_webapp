package Biopay::Transaction;
use Moose;
use methods;
use Dancer::Plugin::CouchDB;
use DateTime;
use Biopay::Member;

use Switch;

use Data::Dumper;

#SP, will leave this hardcoded for now.
#To be moved to DB later. It can have its own class and a website page to update..
# Updates: 
#     11 January 2019 - CT -> 8.95 c/L
#     04 April 2019 - CT -> 10.23 c/L
my $taxes =  {
		'BC' => {motor_fuel => 0.15, carbon => 0.1023, sub_total => 0.05, fuel_excise => 0.04},
		'Vancouver' => {motor_fuel => 0.26, carbon => 0.1023, sub_total => 0.05, fuel_excise => 0.04},
		'Victoria' => {motor_fuel => 0.18, carbon => 0.1023, sub_total => 0.05, fuel_excise => 0.04}
};

extends 'Biopay::Resource';

has 'epoch_time'                   => (isa => 'Num',  is => 'ro', required => 1);
has 'date'                         => (isa => 'Str',  is => 'ro', required => 1);
has 'price_per_litre_diesel'       => (isa => 'Num',  is => 'ro', required => 1);
has 'price_per_litre_biodiesel'    => (isa => 'Num',  is => 'ro', required => 1);
has 'txn_id'                       => (isa => 'Str',  is => 'ro', required => 1);
has 'mix'                          => (isa => 'Str',  is => 'ro', required => 1);
has 'tax_area'					   => (isa => 'Str',  is => 'ro', required => 1);
#SP
#Don't need this without the cardlock
#has 'cardlock_txn_id' => (isa => 'Str',  is => 'ro');
has 'litres'              => (isa => 'Num',  is => 'ro', required => 1);
has 'litres_diesel'       => (isa => 'Num',  is => 'ro', required => 1); #TODO consider lazy_build
has 'litres_biodiesel'    => (isa => 'Num',  is => 'ro', required => 1); #TODO consider lazy_build
has 'member_id'           => (isa => 'Num',  is => 'ro', required => 1);
has 'price'               => (isa => 'Num',  is => 'ro', required => 1);
has 'pump'                => (isa => 'Str',  is => 'ro', required => 1);
has 'paid'                => (isa => 'Bool', is => 'rw', default => 0);
has 'paid_date'           => (isa => 'Num',  is => 'rw');
has 'payment_notes'       => (isa => 'Maybe[Str]',  is => 'rw');

with 'Biopay::Roles::HasMember';

has 'GST'                 => (is => 'ro', isa => 'Num',    lazy_build => 1);
has 'total_taxes'         => (is => 'ro', isa => 'Num',    lazy_build => 1);
has 'carbon_tax'          => (is => 'ro', isa => 'Num',    lazy_build => 1);
has 'motor_fuel_tax'      => (is => 'ro', isa => 'Num',    lazy_build => 1);
has 'fuel_excise_tax'     => (is => 'ro', isa => 'Num',    lazy_build => 1);
has 'tax_rate'            => (is => 'ro', isa => 'Num',    lazy_build => 1);
has 'datetime'            => (is => 'ro', isa => 'Object', lazy_build => 1);
has 'pretty_date'         => (is => 'ro', isa => 'Str',    lazy_build => 1);
has 'pretty_paid_date'    => (is => 'ro', isa => 'Str', lazy_build => 1);
has 'co2_reduction'       => (is => 'ro', isa => 'Num', lazy_build => 1);

#used for receipts and stuff (not the reports)
has 'price_per_litre'     => (is => 'ro', isa => 'Num', lazy_build => 1);

sub view_base {'txns'}
method id { $self->txn_id }
method age_in_seconds { time() - $self->epoch_time }

sub All_unpaid { shift->All_for_view('/unpaid',  @_) }
sub By_date    { shift->All_for_view('/by_date', @_) }

method All_most_recent {
    my %p = @_;
    my $nsk = $p{next_startkey};
    my $page_size = 200;
    my $txns = $self->All_for_view('/recent', 
        {
            ($nsk ? (startkey => 2000000000 - $nsk) : ()),
            limit => $page_size + 1,
        }
    );
    if (@$txns == $page_size + 1) {
        $nsk = pop(@$txns)->epoch_time;
    }
    return {
        next_startkey => $nsk,
        txns => $txns,
    };
}

sub All_for_member {
    my ($class, $key, @args) = @_;
    my $opts = {
        startkey => [$key],
        endkey => [$key, {}],
    };
    $class->All_for_view('/by_member', $opts );
}

after 'paid' => sub {
    my $self = shift;
    return unless $self->{paid} and not $self->paid_date;
    my $now = time;
    $self->paid_date($now);
};

method as_hash {
    my $hash = {};
    for my $key (qw/_id _rev epoch_time date price_per_litre_diesel tax_area
					price_per_litre_biodiesel txn_id paid Type
                    litres litres_diesel litres_biodiesel mix
					member_id price pump paid_date payment_notes/) {
        $hash->{$key} = $self->$key;
    }
    return $hash;
}

method _build_pretty_date {
    my $t = $self->datetime;
    return $t->month_name . ' ' . $t->day . ', ' . $t->year
        . ' at ' . sprintf("%2d:%02d", $t->hour_12, $t->minute) . ' ' . $t->am_or_pm;
}

method _build_pretty_paid_date {
    my $t = DateTime->from_epoch(epoch => $self->paid_date);
    $t->set_time_zone('America/Vancouver');
    return $t->month_name . ' ' . $t->day . ', ' . $t->year
        . ' at ' . sprintf("%02d:%02d", $t->hour_12, $t->minute) . ' ' . $t->am_or_pm;
}

method _build_datetime {
    my $dt = DateTime->from_epoch(epoch => $self->epoch_time);
    $dt->set_time_zone('America/Vancouver');
    return $dt;
}

method _build_GST {
    # Calculate the HST from the total
    # 2012-03-23 - changing HST from 1.05% to 1.12% as per Louise @ RA
    # 2013-04-01 - changing the GST from 1.12% to 1.05 
	my $tax = $taxes->{ $self->tax_area };
	sprintf '%0.02f', $self->price - ( $self->price / (1.0 + $tax->{sub_total}) );
}


#SP these three (carbon_tax, motor_fuel_tax, and fuel_excise_tax attribs) 
#are used for presentation purposes, they are not added to the total charged at the pump.
#The pump already includes taxes in the price-per-litre value configured on the Biopay website.
#There may be small round off issues that cause the sum of these two
#not to be equal to total_taxes...
method _build_carbon_tax {
  	my $tax = $taxes->{ $self->tax_area };
	sprintf '%0.02f', $self->_litres_for_taxes * $tax->{carbon};
}

method _build_motor_fuel_tax {
  	my $tax = $taxes->{ $self->tax_area };
	sprintf '%0.02f', $self->_litres_for_taxes * $tax->{motor_fuel};
}

method _build_fuel_excise_tax {
        my $tax = $taxes->{ $self->tax_area };
        sprintf '%0.02f', $self->_litres_for_taxes * $tax->{fuel_excise};
}

# Price per litre values supplied by the pump include all the taxes. If Price per litre is
# too small or specifically zero, it means the taxes were zero.
method _litres_for_taxes {
	my $tax = $taxes->{ $self->tax_area };
	my $combined_tax_rate = $tax->{carbon} + $tax->{motor_fuel} + $tax->{fuel_excise};
	my $vol = 0;
	$vol += $self->litres_diesel if $self->price_per_litre_diesel > $combined_tax_rate;
	$vol += $self->litres_biodiesel if $self->price_per_litre_biodiesel > $combined_tax_rate;
	return $vol;
}


method _build_total_taxes {
  	my $tax = $taxes->{ $self->tax_area };
	sprintf '%0.02f', $self->GST
        + $self->_litres_for_taxes * $tax->{motor_fuel} #0.24   # Road Fuels Tax
        + $self->_litres_for_taxes * $tax->{carbon}; #0.1023 # Carbon Tax
        + $self->_litres_for_taxes * $tax->{fuel_excise} #0.04 # Fuel excise tax
}

method _build_tax_rate {
    return 0 if $self->price == 0;
    sprintf '%0.01f', $self->total_taxes / $self->price * 100;
}

method _build_co2_reduction {
    return int($self->litres_biodiesel * 1.94);
}

method _build_price_per_litre {
	sprintf '%0.02f', $self->price / $self->litres;
}
