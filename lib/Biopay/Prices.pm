package Biopay::Prices;
use feature 'state';
use Moose;
use Dancer::Plugin::CouchDB;
use Dancer ':syntax';
use Try::Tiny;
use methods;

my @price_fields = qw/price_per_litre_diesel price_per_litre_biodiesel annual_membership_price signup_price/;
for (@price_fields) {
    has $_ => (is => 'rw', isa => 'Num', lazy_build => 1);
}
has '_doc' => (is => 'rw', isa => 'HashRef', lazy_build => 1);

method fuel_price { { diesel => $self->price_per_litre_diesel,
	   				  biodiesel => $self->price_per_litre_biodiesel} }
method BUILD { $self->async_update }

method async_update {
    delete $self->{_doc};
    state $cv;
    return if $cv;
    $cv = couchdb->open_doc("prices");
    $cv->cb( sub {
            my $cv2 = shift;
            my $doc = $cv2->recv;
            for my $pf (@price_fields) {
                die "Did not find '$pf' in the 'prices' doc!"
                    unless $doc->{$pf};
                $self->$pf($doc->{$pf});
            }
            undef $cv;
        },
    );
}

method set_fuel_price($dppl, $bppl) {
    my $doc = $self->_doc;
    $self->{price_per_litre_diesel} = $doc->{price_per_litre_diesel} = $dppl;
    $self->{price_per_litre_biodiesel} = $doc->{price_per_litre_biodiesel} = $bppl;
    couchdb->save_doc($doc);
}

method _build_price_per_litre_diesel {
    my $ppl = $self->_doc->{price_per_litre_diesel} || die "No Diesel price per litre found!";
    print "Price_per_litre_diesel($ppl)";
    return $ppl;
}

method _build_price_per_litre_biodiesel {
    my $ppl = $self->_doc->{price_per_litre_biodiesel} || die "No Biodiesel price per litre found!";
    print "Price_per_litre_biodiesel($ppl)";
    return $ppl;
}

method _build_annual_membership_price {
    return $self->_doc->{annual_membership_price}
        || die "No annual membership price found!";
}

method _build_signup_price {
    return $self->_doc->{signup_price}
        || die "No signup_price found!";
}

method _build__doc {
    my $cv = couchdb->open_doc("prices");
    return try { $cv->recv }
    catch {
        if ($_ =~ m/^404/) {
            die "Could not load the 'prices' doc! Make sure it exists.";
        }
        else { die "Failed to load 'prices' doc: $_" }
    };
}
