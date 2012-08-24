use inc::Module::Install;

name     'WebService-Cmis';
all_from 'lib/WebService/Cmis.pm';
readme_from 'lib/WebService/Cmis.pm';

author   q{Michael Daum <daum@michaeldaumconsulting.com>};
license  'perl';

requires 'XML::LibXML' => 0;
requires 'Error' => 0;
requires 'LWP::UserAgent' => 0;
requires 'URI' => 0;
requires 'REST::Client' => 0;
test_requires 'Test::Pod' => 0;
test_requires 'Test::Class' => 0;
test_requires 'Test::Pod::Coverage' => 0;
test_requires 'Test::DistManifest' => 0;
test_requires 'Test::Signature' => 0;

sign;
WriteAll;
