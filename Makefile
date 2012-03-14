ATSHOME := $(PWD)
ATSHOMERELOC ?= 
ATSOPT ?= ATSHOME=$(ATSHOME) ATSHOMERELOC=$(ATSHOMERELOC) compiler/bin/atsopt
CC ?= gcc
CFLAGS ?= -std=c99 -Wall -Wextra -Wno-unused -march=i386 \
          -Os -m32 -nostdlib -fno-stack-protector \
          -ffunction-sections -fdata-sections -fomit-frame-pointer -g
LDFLAGS ?= -m32 -nostdlib -Wl,--build-id=none
V ?= 0 # Verbosity

SOURCES = prelude/limits.sats \
          portio.sats portio.dats \
          boot.dats vga-text.sats vga-text.dats \
          enablable.sats enablable.dats \
          bitflags.sats bitflags.dats multiboot.sats \
          serial.sats serial.dats trace.sats trace.dats \
          gdt.sats gdt.dats interrupts.sats interrupts.dats

PF_SOURCES = prelude/DATS/integer.dats prelude/DATS/arith.dats

SOURCES := $(SOURCES) $(PF_SOURCES)

ifeq ($(strip $(V)),0)
.SILENT:

ECHO = echo
GENSTR = "    GEN   $<"
ATSSTR = "    ATS   $<"
CCSTR  = "    CC    $<"
LDSTR  = "    LD    $@"
NMSTR  = "    NM    $<"
else
ECHO = @\#
endif

as_sources := start.S isr.S
sats_sources := $(filter %.sats,$(SOURCES))
dats_sources := $(filter %.dats,$(SOURCES))
sats_objects := $(patsubst %.sats,%_sats.o,$(sats_sources))
dats_objects := $(patsubst %.dats,%_dats.o,$(dats_sources))
objects := $(sats_objects) $(dats_objects)
prelude_sources := $(wildcard prelude/SATS/*.sats) prelude/SATS/integer.sats

clean_files := test $(objects) $(objects:.o=.c)

.PHONY: all always compiler

all: kernel syms

# Link twice: once without --gc-sections to check elaborations
# then with --gc-sections to remove unused sections.
kernel: $(objects) $(as_sources) kernel.ld
	$(ECHO) $(LDSTR)
	$(CC) $(LDFLAGS) -Wl,-T,kernel.ld -o $@ $(as_sources) $(objects)
	$(CC) $(LDFLAGS) -Wl,--gc-sections,-T,kernel.ld -o $@ $(as_sources) $(objects)

syms: kernel
	$(ECHO) $(NMSTR)
	nm kernel > syms

# Do all ATS compiling before C compiling. It looks nicer! :-D
$(sats_objects) $(dats_objects): %.o: %.c | $(sats_objects:.o=.c) $(dats_objects:.o=.c)
	$(ECHO) $(CCSTR)
	$(CC) $(CFLAGS) -I. -c -o $@ $<

$(dats_objects:.o=.c): %_dats.c: %.dats $(prelude_sources)
	$(ECHO) $(ATSSTR)
	$(ATSOPT) --output $@ --dynamic $< || { $(RM) $@ ; false ; }

$(sats_objects:.o=.c): %_sats.c: %.sats $(prelude_sources)
	$(ECHO) $(ATSSTR)
	$(ATSOPT) --gline --output $@ --static $< || { $(RM) $@ ; false ; }

prelude/SATS/integer.sats: gen_integer.lua
	$(ECHO) $(GENSTR)
	lua gen_integer.lua > $@ || { $(RM) $@ ; false ; }

.PHONY: depend

depend: prelude/SATS/integer.sats
	$(ECHO) "    Analysing dependencies..."
	$(ATSOPT) -dep1 -s $(sats_sources) -d $(dats_sources) \
		| sed -r 's/^ *([^:]*)\.o *:/\1.c :/' > .depends.mak

.PHONY: clean

clean:
	$(ECHO) "    Cleaning..."
	$(ECHO) "    "$(clean_files)
	$(RM) $(clean_files)

-include .depends.mak

# Check out and build a patched version of the ATS compiler.
compiler:
	[ -e "compiler/" ] || { svn checkout "https://ats-lang.svn.sourceforge.net/svnroot/ats-lang/trunk" "compiler" && patch --directory="compiler/" -Np1 <"ats-anairiats-bignums.patch" ; }
	[ -e "compiler/bootstrap0" ] || svn checkout "https://ats-lang.svn.sourceforge.net/svnroot/ats-lang/bootstrap/anairiats" "compiler/bootstrap0"
	[ -e "compiler/configure" ] || { cd "compiler/" && { aclocal ; automake --add-missing ; autoconf ; } ; }
	[ -e "compiler/config.h" ] || { cd "compiler/" && ./configure ; }
	[ -e "compiler/bin/atsopt" ] || { cd "compiler/" && $(MAKE) all ; }
