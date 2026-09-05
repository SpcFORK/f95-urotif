FC = gfortran
CARGO ?= cargo
RUSTC ?= rustc
CC ?= gcc
FFLAGS ?= -O2 -Wall -Wextra -Wno-compare-reals -fcheck=all -fbacktrace -fmax-stack-var-size=1048576 -Ifortran
CORE = build/urotif_types.o build/urotif_limits.o build/urotif_lexer.o build/urotif_parser.o build/urotif_vm.o build/urotif_host_api.o build/urotif_prototype.o
RUSTLIB = rust-chain/target/release/liburotif_chain.a
# Linux defaults. Override on another OS using rustc --print=native-static-libs.
RUST_NATIVE_LIBS ?= -ldl -lpthread -lm -lrt -lutil
.PHONY: all core95 test test-reference test-foundation test-roundtrip test-typed sanitize sanitize-typed benchmark clean examples foundation-examples plugins typed-plugins typed-examples check-repo source-bundle
all: bin/urotif
core95: bin/urotif95
build bin:
	mkdir -p $@
build/urotif_types.o: fortran/urotif_types.f90 | build
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_limits.o: fortran/urotif_limits.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_lexer.o: fortran/urotif_lexer.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_parser.o: fortran/urotif_parser.f90 build/urotif_lexer.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_vm.o: fortran/urotif_vm.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_host_api.o: fortran/urotif_host_api.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_host_stub.o: fortran/urotif_host_stub.f90 build/urotif_host_api.o
	$(FC) $(FFLAGS) -Wno-unused-dummy-argument -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_preprocess.o: fortran/urotif_preprocess.f90 build/urotif_lexer.o build/urotif_limits.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_assembler.o: fortran/urotif_assembler.f90 build/urotif_preprocess.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_foundation_ir.o: fortran/urotif_foundation_ir.f90 build/urotif_limits.o build/urotif_lexer.o build/urotif_host_api.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_foundation_bridge.o: fortran/urotif_foundation_bridge.f90 build/urotif_foundation_ir.o
	$(FC) $(FFLAGS) -std=f2003 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_typed_abi.o: fortran/urotif_typed_abi.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f2003 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_typed_links.o: fortran/urotif_typed_links.f90 build/urotif_typed_abi.o build/urotif_links.o
	$(FC) $(FFLAGS) -std=f2003 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_links.o: fortran/urotif_links.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f2003 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_prototype.o: fortran/urotif_prototype.f90 fortran/foundation_methods.inc fortran/byte_helpers.inc fortran/typed_methods.inc fortran/prototype_driver.inc build/urotif_limits.o build/urotif_lexer.o build/urotif_host_api.o
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/urotif_bridge.o: fortran/urotif_bridge.f90 build/urotif_types.o
	$(FC) $(FFLAGS) -std=f2003 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/main.o: fortran/main.f90 $(CORE) build/urotif_bridge.o build/urotif_typed_abi.o build/urotif_typed_links.o build/urotif_links.o build/urotif_foundation_bridge.o build/urotif_preprocess.o build/urotif_assembler.o
	$(FC) $(FFLAGS) -std=f2003 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
build/main_f95.o: fortran/main_f95.f90 $(CORE)
	$(FC) $(FFLAGS) -std=f95 -pedantic-errors -Jbuild -Ibuild -c $< -o $@
$(RUSTLIB): rust-chain/Cargo.toml rust-chain/Cargo.lock $(wildcard rust-chain/src/*.rs) runtime/foundation.rs runtime/foundation.c $(wildcard runtime/typed*) $(wildcard include/*.h) $(wildcard runtime/*.f90) $(wildcard fortran/*.f90) $(wildcard fortran/*.inc)
	$(CARGO) build --manifest-path rust-chain/Cargo.toml --release --locked
bin/urotif: $(CORE) build/urotif_bridge.o build/urotif_typed_abi.o build/urotif_typed_links.o build/urotif_links.o build/urotif_foundation_ir.o build/urotif_foundation_bridge.o build/urotif_preprocess.o build/urotif_assembler.o build/main.o $(RUSTLIB) | bin
	$(FC) $(FFLAGS) $(CORE) build/urotif_bridge.o build/urotif_typed_abi.o build/urotif_typed_links.o build/urotif_links.o build/urotif_foundation_ir.o build/urotif_foundation_bridge.o build/urotif_preprocess.o build/urotif_assembler.o build/main.o $(RUSTLIB) $(RUST_NATIVE_LIBS) -o $@
bin/urotif95: $(CORE) build/urotif_host_stub.o build/main_f95.o | bin
	$(FC) $(FFLAGS) $(CORE) build/urotif_host_stub.o build/main_f95.o -o $@
test: test-reference test-foundation test-roundtrip test-typed
test-reference: all core95
	$(CARGO) test --manifest-path rust-chain/Cargo.toml --locked
	python3 tests/test_pipeline.py
test-foundation: all
	python3 tests/test_foundation.py
test-roundtrip: all
	python3 tests/test_roundtrip.py
test-typed: all
	python3 tests/test_typed.py
	node --test tests/test_wasm_links.mjs
sanitize-typed: all
	python3 tools/sanitize_typed.py
sanitize: all
	python3 tools/sanitize_foundation.py
benchmark: all
	python3 tools/benchmark_foundation.py
plugins: build/demo.so build/demo.o build/rust_demo.so typed-plugins
build/demo.so: plugins/demo.c include/urotif_plugin.h | build
	$(CC) -std=c99 -O3 -shared -fPIC $< -o $@
build/demo.o: plugins/demo.c include/urotif_plugin.h | build
	$(CC) -std=c99 -O3 -DUROTIF_STATIC_LINK -c $< -o $@
build/rust_demo.so: plugins/rust_demo.rs | build
	$(RUSTC) --edition=2021 -O --crate-type=cdylib $< -o $@
foundation-examples: all plugins
	mkdir -p artifacts/foundation
	bin/urotif assemble examples/foundation/square.ufm -o examples/foundation/square-assembled.utf
	bin/urotif assemble examples/foundation/truth.ufm -o examples/foundation/truth-assembled.utf
	@for name in external truth subroutine plugin; do \
	  extra=''; test "$$name" != plugin || extra='--extern demo.cube/1'; \
	  for target in c rust wasm; do \
	    ext=$$target; test "$$target" != rust || ext=rs; \
	    bin/urotif $$target examples/foundation/$$name.utf --foundation $$extra -o artifacts/foundation/$$name.$$ext || exit 1; \
	  done; \
	done

examples: all
	mkdir -p artifacts/wasm
	@for f in examples/core/*.utf; do bin/urotif wasm "$$f" --core -o "artifacts/wasm/$$(basename "$$f" .utf).wasm" || exit 1; done
clean:
	rm -rf build bin
	$(CARGO) clean --manifest-path rust-chain/Cargo.toml

# ABI-2 services: dynamic native loading or canonical static target bindings.
typed-plugins: build/buffers.so build/buffers.o build/unicode.so build/libunicode.a
build/buffers.so: plugins/buffers.c include/urotif_plugin_v2.h include/urotif_typed_values.h | build
	$(CC) -std=c99 -O2 -shared -fPIC $< -lm -o $@
build/buffers.o: plugins/buffers.c include/urotif_plugin_v2.h include/urotif_typed_values.h | build
	$(CC) -std=c99 -O2 -DUROTIF_STATIC_LINK -c $< -o $@
build/unicode.so: plugins/unicode.rs runtime/typed_abi.rs | build
	$(RUSTC) --edition=2021 -O -A dead_code --crate-type=cdylib $< -o $@
build/libunicode.a: plugins/unicode.rs runtime/typed_abi.rs | build
	$(RUSTC) --edition=2021 -O -A dead_code -A unused_imports --crate-type=staticlib --cfg urotif_static_link $< -o $@
typed-examples: all plugins
	python3 tools/show_typed_transpilation.py

# Source-only repository/release hygiene (no compiler build required).
check-repo:
	python3 tools/check_repository.py
source-bundle:
	python3 tools/package_source.py
