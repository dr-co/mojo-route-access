#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 22;
use Encode qw(decode encode);


BEGIN {
    use_ok 'Test::Mojo';
}

package Test::RouteAccess;
use Mojo::Base 'Mojolicious';

sub startup {

    my ($self) = @_;

    $self->plugin('RouteAccess');
    $self->add_route_access(
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
                    return undef unless $check and $check eq 'nf';
                    return 0;
            }
        )
        ->add_route_access_condition('number')
        ->add_route_access_condition(mycheck => 'number')
    ;

    for my $r ($self->routes) {
        $r  -> get('/ping')
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(text => 'pong');
                }
            );

        $r  -> get('/number/:bla')
            -> over(access => {number => 'bla'})
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(json => { bla => $self->stash('blabla') });
                }
            );

        $r  -> get('/over_condition/:bla')
            -> over(number => 'bla')
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(json => { bla => $self->stash('blabla') });
                }
            );

        $r  -> get('/over_alias/:bla')
            -> over(mycheck => 'bla')
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(json => { bla => $self->stash('blabla') });
                }
            );

        $r  -> get('/multi/:bla')
            -> over(
                number  => 'bla',
                access  => {number => 'bla'},
            )
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(json => {
                        bla => $self->stash('blabla'),
                        old => $self->stash('oldbla')
                    });
                }
            );
    }
}

package main;

my $t = new Test::Mojo('Test::RouteAccess');
ok $t => 'Test instance created';

$t  -> get_ok('/ping')
    -> status_is(200)
    -> content_is('pong')
;

$t  -> get_ok('/number/1')
    -> status_is(200)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/bla', 1 * 2)
;

$t  -> get_ok('/over_condition/1')
    -> status_is(200)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/bla', 1 * 2)
;

$t  -> get_ok('/over_alias/1')
    -> status_is(200)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/bla', 1 * 2)
;

$t  -> get_ok('/multi/1')
    -> status_is(200)
    -> header_like('Content-Type', qr{application/json})
    -> json_is('/bla', 1 * 2)
    -> json_is('/old', 1 * 2)
;
