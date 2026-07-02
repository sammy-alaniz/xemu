mcpx_ss.add(files(
	'apu.c',
	'debug.c',
	'monitor.c',
	))
if not get_option('xemu_browser_boot')
	mcpx_ss.add(sdl)
endif

subdir('vp')
if not get_option('xemu_browser_boot')
	subdir('dsp')
else
	mcpx_ss.add(files('dsp-stubs.c'))
endif
