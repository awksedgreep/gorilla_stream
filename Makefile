# Output directory: elixir_make sets MIX_APP_PATH; fall back to local priv/
PRIV_DIR ?= $(if $(MIX_APP_PATH),$(MIX_APP_PATH)/priv,priv)
NIF_SO = $(PRIV_DIR)/gorilla_nif.so

# Erlang NIF headers
ERTS_INCLUDE_DIR ?= $(shell erl -noshell -eval "io:format(\"~s/erts-~s/include\", [code:root_dir(), erlang:system_info(version)])." -s init stop)

# Fine headers
FINE_INCLUDE_DIR ?= $(shell elixir -e "IO.write(Fine.include_dir())")

# Compiler settings
CXX ?= c++
CXXFLAGS = -std=c++17 -O2 -fPIC -fvisibility=hidden -Wall -Wextra -Wno-unused-parameter
CXXFLAGS += -I$(ERTS_INCLUDE_DIR)
CXXFLAGS += -I$(FINE_INCLUDE_DIR)

# Platform-specific linker flags
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	LDFLAGS = -dynamiclib -undefined dynamic_lookup
else
	LDFLAGS = -shared
endif

# Sources
NIF_SRC = c_src/gorilla_nif.cpp
NIF_OBJ = c_src/gorilla_nif.o

.PHONY: all clean check-compiler

# Verify that the C++ compiler exists and supports C++17 before attempting to build.
check-compiler:
	@command -v $(CXX) >/dev/null 2>&1 || \
		{ echo "ERROR: C++ compiler '$(CXX)' not found. See README.md for platform-specific installation instructions."; exit 1; }
	@$(CXX) -std=c++17 -x c++ - -fsyntax-only </dev/null 2>/dev/null || \
		{ echo "ERROR: '$(CXX)' does not support C++17. Please use GCC >= 7 or Clang >= 5. See README.md for details."; exit 1; }

all: $(PRIV_DIR) $(NIF_SO)

$(PRIV_DIR):
	mkdir -p $(PRIV_DIR)

$(NIF_OBJ): $(NIF_SRC)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

$(NIF_SO): $(NIF_OBJ) | $(PRIV_DIR)
	$(CXX) $(LDFLAGS) -o $@ $(NIF_OBJ)

clean:
	rm -f $(NIF_SO) $(NIF_OBJ)
