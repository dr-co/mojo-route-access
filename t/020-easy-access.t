#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 33;
use Encode qw(decode encode);


BEGIN {
    use_ok 'Test::Mojo';
}

package Test::RouteAccess;
use Mojolicious::Lite;

get '/ping' => sub {
    my ($self) = @_;
    $self->render(text => 'pong');
};


get '/die', { access => 'die' } => sub {
    die 'da36f346-3c99-11e7-996f-0b3616705d19'
};


get '/number/:bla', { access => {number => 'bla'} } => sub {
    my ($self) = @_;
    $self->render(json => { bla => $self->stash('blabla') });
};

get '/undef-check', { access => 'number' } => sub {
    my ($self) = @_;
    $self->render(json => { bla => $self->stash('blabla') });
};

under('/bridge/:bla', { access => { number => 'bla' } })
    -> get(':ble', { access => { number => [ 'bla', 'ble' ] }}, sub {
        my ($self) = @_;
        $self->render(json => {
            bla => $self->stash('blabla'),
            old => $self->stash('oldbla')
        });
    })
;

plugin 'RouteAccess';

app->add_route_access(
    die     => sub {
        die "99f463ae-3c99-11e7-9e18-ef793f14b189";
    },

    number    => sub {
        my ($self, $check, $stash) = @_;

        goto nf unless $check;
        goto nf unless $check =~ /^\d+$/;

        $self->stash(oldbla => $self->stash('blabla'));
        $self->stash(blabla => $check * 2);
        return 1;

        nf:
            $self->render(
                status => 403,
                json => {
                    status => '68f2a6ca-3ca4-11e7-815b-8767618c5cec'
                });
            return unless $check and $check eq 'nf';
            return 0;
    }
);



package main;

my $t = new Test::Mojo('Test::RouteAccess');
ok $t => 'Test instance created';

$t  -> get_ok('/ping')
    -> status_is(200)
    -> content_is('pong')
;

$t  -> get_ok('/die')
    -> status_is(500)
    -> content_unlike(qr{da36f346-3c99-11e7-996f-0b3616705d19})
    -> content_like(qr{99f463ae-3c99-11e7-9e18-ef793f14b189})
;

$t  -> get_ok('/number/1')
    -> status_is(200)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/bla', 1 * 2)
    
    -> get_ok('/number/1024')
    -> status_is(200)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/bla', 1024 * 2)
;

$t  -> get_ok('/number/abc')
    -> status_is(403)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/status', '68f2a6ca-3ca4-11e7-815b-8767618c5cec')
    -> json_is('/bla', undef)
;

$t  -> get_ok('/number/nf')
    -> status_is(404)
    -> content_unlike(qr{68f2a6ca-3ca4-11e7-815b-8767618c5cec})
;

$t  -> get_ok('/undef-check')
    -> status_is(403)
    -> json_is('/status', '68f2a6ca-3ca4-11e7-815b-8767618c5cec')
    -> json_is('/bla', undef)
;

$t  -> get_ok('/bridge/3/24')
    -> status_is(200)
    -> json_is('/bla', 24 * 2)
    -> json_is('/old', 3 * 2)
;
