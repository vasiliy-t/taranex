package = 'taranex'
version = 'scm-1'
source  = {
    url = '/dev/null',
}
-- Put any modules your app depends on here
dependencies = {
    'tarantool',
    'lua >= 5.1',
    'cartridge == 2.1.2-1',
    'icu-date',
    'checks'
}
build = {
    type = 'none';
}
