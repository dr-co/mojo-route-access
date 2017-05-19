package Mojolicious::Plugin::RouteAccess;
use Mojo::Base 'Mojolicious::Plugin';
use Carp;

our $VERSION = '0.01';

use Data::Dumper;


sub register {
    my ($self, $app, $conf) = @_;


    $conf ||= {};
    $conf->{list} //= {};

    $app->helper(add_route_access => sub {
        my ($self, %list) = @_;

        while (my ($name, $cb) = each %list) {
            croak "Usage \$app->add_access(my_accessor => sub { ... })"
                unless $name and 'CODE' eq ref $cb;


            my $list = $conf->{list};
            croak "Access checker '$name' has already added to list"
                if exists $list->{$name};

            $list->{$name} = $cb;
        }

        $self;
    });

    $app->hook(around_action => sub {
        my ($next, $self, $action, $last) = @_;
        my $access = $self->stash('access');
        return $next->() unless $access;

        $access = { $access => undef } unless 'HASH' eq ref $access;

        my $list = $conf->{list};

        for (keys %$access) {
            unless (exists $list->{$_}) {
                $self->reply->not_found;
                return;
            }

            my $checks = $access->{$_};
            $checks = [ $checks ] unless 'ARRAY' eq ref $checks;

            my $res;
            for my $v (@$checks) {
                $res = $list->{$_}->($self, $v);
                next if $res;
                if (defined $res) {
                    $self->reply->not_found;
                    return;
                }
                return;
            }
        }

        return $next->();
    });
}

1;
