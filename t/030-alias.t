#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib t/lib);

use Test::More tests    => 38;
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
            },

            number_ifstash => sub {
                my ($self, $check, $stash) = @_;
                return unless $self->stash('blabla');
                return unless $check =~ /^\d+$/;
                $self->stash('ifstash', 1);
                return 1;
            },

            twice_number => sub {
                my ($self, $v1, $v2, $name1, $name2) = @_;
                return unless defined $v1 and $v1 =~ /^\d+$/;
                return unless defined $v2 and $v2 =~ /^\d+$/;

                $self->stash('s1', $v1);
                $self->stash('s2', $v2);
                return 1;
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

        $r  -> get('/ary/:bla')
            -> over(access => [ 'number#bla', 'number_ifstash#bla' ])
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(json => {
                        bla => $self->stash('blabla'),
                        if  => $self->stash('ifstash')
                    });
            });
        
        $r  -> get('/rary/:bla')
            -> over(access => [ 'number_ifstash#bla', 'number#bla' ])
            -> to(cb => sub {
                    my ($self) = @_;
                    $self->render(json => {
                        bla => $self->stash('blabla'),
                        if  => $self->stash('ifstash')
                    });
            });

        $r  -> get('/twice/:bla/:ble')
            -> over(access => [ 'twice_number#bla,ble' ])
            -> to(cb => sub {
                my ($self) = @_;
                $self->render(json => {
                    bla => $self->stash('bla'),
                    ble => $self->stash('ble'),
                    s1  => $self->stash('s1'),
                    s2  => $self->stash('s2'),
                });
            });
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
#     -> content_is('')
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

$t  -> get_ok('/ary/123')
    -> status_is(200)
    -> json_is('/bla', 2 * 123)
    -> json_is('/if', 1)
;

$t  -> get_ok('/rary/123')
    -> status_is(404)
;

$t  -> get_ok('/twice/123/abc')
    -> status_is(404)
    -> get_ok('/twice/abc/123')
    -> status_is(404)

    -> get_ok('/twice/123/345')
    -> status_is(200)
    -> json_is('/bla', 123)
    -> json_is('/s1', 123)
    -> json_is('/ble', 345)
    -> json_is('/s2', 345)
;
