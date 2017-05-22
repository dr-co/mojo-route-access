package Mojolicious::Plugin::RouteAccess;
use Mojo::Base 'Mojolicious::Plugin';
use Carp;

our $VERSION = '0.02';

use Data::Dumper;
use constant CONDNAME       => 'access';
use constant STASHNAME      => 'mojo.access.list';

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

    $app->routes->add_condition(CONDNAME() => sub {
        my ($r, $self, $capture, $access) = @_;

        unless (ref $access) {
            my ($k, $v) = split /#/, $access, 2;
            $access = { $k, $v };
        }

        croak "Usage: \$r->over(access => { access_name => 'stash'  })"
            unless 'HASH' eq ref $access;

        # TODO: HACK: uses req->{var} as stash ($self->stash can be redefined
        # from time to time)
        $self->req->{STASHNAME()} //= [];
        my $stash = $self->req->{STASHNAME()};

        my $list = $conf->{list};
        
        for (keys %$access) {
            return 0 unless exists $list->{$_};
            my $v = $access->{$_};
            $v = [ $v ] unless 'ARRAY' eq ref $v;
            push @$stash => [ $_, $v ];
        }

        return 1;
    });

    $app->hook(around_action => sub {
        my ($next, $self, $action, $last) = @_;
        
        # TODO: HACK: uses req->{var} as stash ($self->stash can be redefined
        # from time to time)
        my $access = delete $self->req->{ STASHNAME() };

        return $next->() unless $access;

        my $list = $conf->{list};

        for (@$access) {
            my ($n, $checks) = @$_;
            unless (exists $list->{$n}) {
                $self->reply->not_found;
                return;
            }

            my %checked;

            my @res;
            for my $v (@$checks) {
                my $sv;
                $sv = $self->stash($v) if defined $v;
                
                my $key = '';
                $key .= qq{"$sv"} if defined $sv;
                $key .= '::';
                $key .= qq{"$v"} if defined $v;
                next if $checked{$key};
                
                @res = $list->{$n}->($self, $sv, $v);
                $res[0] = 0 unless @res;
                if ($res[0]) {
                    $checked{$key} = 1;
                    next;
                }
                
                $self->reply->not_found if defined $res[0];
                return;
            }
        }

        return $next->();
    });
}

1;

__END__

=encoding utf-8

=head1 NAME

Mojolicious::Plugin::RouteAccess - Mojolicious plugin controller route access.

=head1 SYNOPSIS

    package MyController;
    use Mojo::Base 'Mojolicious::Controller';

    sub myaction {
        my ($self) = @_;
        my $myobject = $self->stash('myobject');
        # use $myobject
        $self->render(myobject => $myobject);
    }

    package MyApplication;

    sub startup {
        my ($self) = @_;
        $self->plugin('RouteAccess');
        
        # ...

        $self->routes
            -> get('/edit-myobject/:id')
            -> over(access => { mycheck => 'id' })
            -> to('my_controller#myaction')
            -> name('bla');


        $ctx->add_route_access(mycheck => sub {
            my ($ctx, $id, $stashname) = @_;

            my $myobject = Database->load(id => $id);
            return unless $ctx->authen_user->has_permit_to_edit($myobject);
            $ctx->stash(myobject => $myobject);
            return 1;
        });
    }

=head1 DESCRIPTION

The plugin allow You to access/deny database objects for Your site's users by
route stash.

Example: C<authen_user> can edit C<Object1> but can't edit C<Object2>.

You can add a callback (L<add_route_access>) that checks if C<authen_user> can
edit C<Object> and return C<0> (C<undef>) or C<1>.


The module add C<access> condition that receives scalar or hashref definition
for route checker:

    $r  -> get('/bla')
        -> over(access => 'mycheck')
        -> to(...);

    # the same:
    $r  -> get('/bla')
        -> over(access => { mycheck => undef })
        -> to(...);


=head1 METHODS

=head2 add_route_access($name, sub { ... })

Add checker to list.

Checker - is a callback that receive the following arguments:

=over

=item ctx

Final controller.

=item value

Stash value. C</bla/:id> => C</bla/123> will contain C<123>.

=item stashname

Stash name. C</bla/:id> => C</bla/123> will contain C<id>.

=back

=head1 AUTHORS

L<Dmitry E. Oboukhov (unera@debian.org)|mailto:unera@debian.org>

L<Roman V. Nikolaev (rshadow@rambler.ru)|mailto:rshadow@rambler.ru>

=head1 LICENSE

Copyright (C) 2017 Dmitry E. Oboukhov L<mailto:unera@debian.org>

Copyright (C) 2011 Roman V. Nikolaev L<mailto:rshadow@rambler.ru>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
