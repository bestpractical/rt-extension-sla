use inc::Module::Install;

RTx ('RT-Extension-SLA');
author ('Ruslan Zakirov <ruz@bestpractical.com>');
license('perl');

build_requires('Test::More');

requires('Business::SLA');
requires('Business::Hours');
auto_install();

WriteAll();
