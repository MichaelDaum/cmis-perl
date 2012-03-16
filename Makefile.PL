use inc::Module::Install;

name     'WebService-Cmis';
all_from 'lib/WebService/Cmis.pm';
author   q{Michael Daum <daum@michaeldaumconsulting.com>};
license  'perl';

build_requires 'Test::More';

auto_install;

WriteAll;

