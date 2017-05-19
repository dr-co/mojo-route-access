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
                my $sv;
                $sv = $self->stash($v) if defined $v;
                $res = $list->{$_}->($self, $sv, $v);
                next if $res;
                $self->reply->not_found if defined $res;
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
            -> get('/edit-myobject/:id', access => { mycheck => 'id' })
            -> to('my_controller#myaction')
            -> name('bla');


        $ctx->add_route_access(mycheck => sub {
            my ($ctx, $id) = @_;

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


=head1 METHODS

=head2 add_route_access($name, sub { ... })

Add checker to list.
