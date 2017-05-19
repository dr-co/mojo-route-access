use 5.010001;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'Mojolicious::Plugin::RouteAccess',
    VERSION_FROM      => 'lib/Mojolicious/Plugin/RouteAccess.pm',
    PREREQ_PM         => {
        Mojolicious             => '5',    
    },
    ABSTRACT_FROM     => 'lib/Mojolicious/Plugin/RouteAccess.pm',
    AUTHOR            => 'Dmitry E. Oboukhov <unera@>',
    LICENSE           => 'perl',
);
