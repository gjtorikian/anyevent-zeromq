use strict;
use warnings;
use Test::More;

use EV;
use AnyEvent::ZeroMQ::Handle;
use ZeroMQ::Raw;
use ZeroMQ::Raw::Constants qw(ZMQ_SUBSCRIBE ZMQ_PUB ZMQ_SUB ZMQ_NOBLOCK);

my $c   = ZeroMQ::Raw::Context->new( threads => 10 );
my $pub = ZeroMQ::Raw::Socket->new($c, ZMQ_PUB);
my $sub = ZeroMQ::Raw::Socket->new($c, ZMQ_SUB);
$pub->bind('tcp://127.0.0.1:1234');
$sub->connect('tcp://127.0.0.1:1234');
$sub->setsockopt(ZMQ_SUBSCRIBE, '');

my $pub_h = AnyEvent::ZeroMQ::Handle->new( socket => $pub );
my $sub_h = AnyEvent::ZeroMQ::Handle->new( socket => $sub );

ok $pub_h, 'got publish handle';
ok $sub_h, 'got subscribe handle';

my $cv = AnyEvent->condvar;
$cv->begin for 1..2; # read x2

my ($a, $b);
$sub_h->push_read(sub {
    my ($h, $data) = @_;
    $a = $data;
    $cv->end;
});

$sub_h->push_read(sub {
    my ($h, $data) = @_;
    $b = $data;
    $cv->end;
});

my $made_b = 0;
$pub_h->push_write('a');
$pub_h->push_write(sub { $made_b = 1; return 'b' });

$cv->recv;

is $a, 'a', 'got a';
is $b, 'b', 'got b';
ok $made_b, 'and b was generated by code';

# test the on_read callback
my @r;
$cv = AnyEvent->condvar;
$cv->begin for 1..2;
$sub_h->on_read(sub { push @r, $_[1]; $cv->end });
$pub_h->push_write(ZeroMQ::Raw::Message->new_from_scalar('c'));
$pub_h->push_write(sub { ZeroMQ::Raw::Message->new_from_scalar('d') });
$cv->recv;
is_deeply \@r, [qw/c d/], 'read stuff via on_read';

# test that nothing is sent when we return nothing from a callback
ok !$sub_h->readable, 'nothing to read from subscription handle';
$cv = AnyEvent->condvar;
$pub_h->push_write( sub { $cv->send; return } );
$cv->recv;
ok !$sub_h->readable, "still not readable, since we didn't write anything";

# test that on_error gets errors when we are bad.

# also, writes on pubsub are guaranteed not to block, so we take
# advantage of that guarantee for maximum not having to type the word
# condvar.  except I just did, so that was pointless.

my $error;
$pub_h->on_error( sub { $error = shift } );
$pub_h->push_write( sub { die 'oh noes' } );
like $error, qr/oh noes/, 'got error via callback';
# TODO: test the warning with Test::Warnings or something

# ensure that no watchers remain
$sub_h->clear_on_read;
$sub_h->read;
EV::loop();

done_testing;
