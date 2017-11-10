package Mojolicious::Plugin::RouteAccess;
use Mojo::Base 'Mojolicious::Plugin';
use Carp;

our $VERSION = '0.06';

use constant CONDNAME       => 'access';
use constant STASHNAME      => 'mojo.access.list';
use constant UNDEF_STR      => '37e6ab68c5f111e7a26687cee246a43a';
use Data::Dumper;
sub register {
    my ($self, $app, $conf) = @_;


    $conf ||= {};
    $conf->{list} //= {};

    $app->helper(add_route_access => sub {
        my ($self, %list) = @_;

        while (my ($name, $cb) = each %list) {
            croak "Usage \$app->add_route_access(my_accessor => sub { ... })"
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

        $access = [ $access ] unless 'ARRAY' eq ref $access;
        
        for my $a (@$access) {
            unless (ref $a) {
                my ($k, $v) = split /#/, $a, 2;
                $a = { $k, $v };
            }
        }

        # TODO: HACK: uses req->{var} as stash ($self->stash can be redefined
        # from time to time)
        my $stash = $self->req->{STASHNAME()} //= [];

        my $list = $conf->{list};

        for my $a (@$access) {
            for my $k (keys %$a) {
                return 0 unless exists $list->{$k};
                my $v = $a->{$k};
                $v = [ $v ] unless 'ARRAY' eq ref $v;

                for (@$v) {
                    unless (defined $_) {
                        $_ = [ undef ];
                        next;
                    }
                    $_ = [ split /\s*,\s*/, $_ ];
                }
                push @$stash => [ $k, $v ];
            }
        }
        return 1;
    });

    $app->helper(add_route_access_condition => sub {
        my ($self, $alias, $k) = @_;

        $k //= $alias;

        my $list = $conf->{list};
        croak "Access checker '$k' not added to list"
                unless exists $list->{$k};

        $self->app->routes->add_condition($alias => sub{
            my ($r, $self, $captures, $pattern) = @_;

            my $v = $pattern;
            $v = [ $v ] unless 'ARRAY' eq ref $v;
                
            for (@$v) {
                unless (defined $_) {
                    $_ = [ undef ];
                    next;
                }
                $_ = [ split /\s*,\s*/, $_ ];
            }

            my $stash = $self->req->{STASHNAME()} //= [];
            push @$stash => [ $k, $v ];

            return 1;
        });

        $self;
    });

    $app->hook(around_action => sub {
        my ($next, $self, $action, $last) = @_;

        return $next->() unless $last;

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
                my @sv = map { defined($_) ? $self->stash($_) : undef  } @$v;

                my $key = join '-', map { $_ // UNDEF_STR } @$v;
                $key .= '=';
                $key .= join '-', map { $_ // UNDEF_STR } @sv;
                next if $checked{$key};

                @res = $list->{$n}->($self, @sv, @$v);

                if (@res) {
                    if ($res[0]) {                      # true
                        $checked{$key} = 1;
                        next;
                    }
                    return unless defined $res[0];      # undef
                }

                # return или return FALSE попадает сюда
                $self->reply->not_found;
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

        # ...

        # You can use spimple conditions for check:
        $self->routes
            -> get('/edit-myobject/:id')
            -> over(mycheck => 'id')
            -> to('my_controller#myaction')
            -> name('bla');

        $ctx
            ->add_route_access(mycheck => sub {...})
            ->add_route_access_condition('mycheck')

            # you can add alias
            ->add_route_access_condition('foocheck' => 'mycheck')
        ;
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

You can add several accesses one-by-one:

    $r  -> get('bla/:id')
        -> over(access => [
                    'number#id',
                    'more_than_10#id',
                    ...
        ])
        -> to(...);

Second handler will be started (checked) after the first.

If stashname contains commas, the name will be splitted and all stashes will
be extracted before access sub is called.


    $ctx->add_route_access(mycheck => sub {
        my ($ctx, $id, $hash, $stashname_id, $stashname_hash) = @_;

        my $myobject = Database->load(id => $id);
        return unless $myobject;
        return unless $myobject->hash eq $hash;
        return 1;
    });

    ...
    $r  -> get('/api/:id/:hash/method')
        -> over(access => 'mycheck#id,hash')
        -> to('myctx#method')
        -> name('my_method_name');


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


Checker can return:

=over

=item C<true> (scalar).

Access passed. Controller will be run.

=item C<false> (scalar) or C<none> (C<return;>)

Access denined. Controller will not be run. C<<$app->not_found>> will
be run.

=item C<undef> (scalar).

Access denined. Controller will not be run. C<<$app->not_found>> will
not be run.

=back

=head2 add_route_access($name)

=head2 add_route_access($alias, $name)

Add simple condition for checker.


=head1 AUTHORS

L<Dmitry E. Oboukhov (unera@debian.org)|mailto:unera@debian.org>

L<Roman V. Nikolaev (rshadow@rambler.ru)|mailto:rshadow@rambler.ru>

=head1 LICENSE

Copyright (C) 2017 Dmitry E. Oboukhov L<mailto:unera@debian.org>

Copyright (C) 2011 Roman V. Nikolaev L<mailto:rshadow@rambler.ru>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.
