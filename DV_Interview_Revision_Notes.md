# DV Interview Revision Notes
*Compiled from prep sessions — SystemVerilog fundamentals through UVM. Callouts marked ⚠️ are things that were initially wrong, backwards, or forgotten — re-read these first.*

---

## 1. SystemVerilog Data Types

### Core facts
- **`logic`** merges reg/wire assignment rules but disallows multiple drivers. Any multi-driver net (tri-state bus, wired-OR) must be `wire`/`tri`.
- **`reg` does NOT mean flip-flop.** ⚠️ It's legacy naming — just means "must be assigned procedurally" (inside `always`/`initial`). Whether it synthesizes to a flop depends on the always-block style, not the type.
- **2-state (`bit`, `int`) vs 4-state (`logic`, `integer`)**: 4-state carries `x`/`z`, essential in RTL for X-propagation bug detection. Testbenches often use 2-state for speed, but:
  - ⚠️ **Danger**: casting a 4-state DUT output (possibly `x` due to a real bug) into a 2-state scoreboard variable **silently truncates x→0**, no warning. If your reference model coincidentally also expects 0 there, the checker passes despite a real X-propagation bug. **Fix**: monitors must stay 4-state; use `$isunknown()` explicitly before any 2-state conversion.

### Arrays, Queues, Associative Arrays
- **Dynamic arrays**: ⚠️ CAN be resized via `new[]` again (`new[20](arr)` preserves old data via the copy argument) — not fixed after first init.
- **Queues** (not dynamic arrays) are the standard idiom for FIFO/transaction-tracking (push_back/pop_front) — unpredictable population count.
- **Associative arrays**: sparse allocation, ideal for large memory models (only touched addresses cost storage).
- **Auto-vivification**: writing to a non-existent assoc-array key auto-creates it — often no `.exists()` check needed before a write.
- ⚠️ **`.exists(key)` is called ON THE ARRAY with the key as argument** — `arr.exists(key)`, never `arr[key].exists()` (the latter also has the side effect of auto-vivifying a bogus entry).

### Packed vs Unpacked
- **Struct default is UNPACKED.** ⚠️ Must write `packed` explicitly to get one contiguous bit-vector layout.
- **First-declared member of a packed struct = MSB, last-declared = LSB.** ⚠️ (Got this backwards twice — always trace struct layout before indexing/manually unpacking.)
- Array packed vs unpacked is determined by **dimension position**: `bit[3:0][7:0] x` (before name) = packed; `bit[7:0] x[3:0]` (after name) = unpacked. Part-select only works across packed/contiguous dimensions.
- **`$cast` is unnecessary** for same-width packed-struct ↔ bit-vector — direct assignment works, since it's already one contiguous bit-vector.

### Part-select & Streaming
- `[msb:lsb]` — both bounds must be **constants**.
- `[base +: width]` / `[base -: width]` — `base` can be a variable, `width` must be constant. `+:` walks up from base; `-:` walks down from base.
- Streaming `{>>{...}}` (MSB-first) / `{<<{...}}` (LSB-first): ⚠️ **direction must be re-derived every time** by tracing which end of the source maps to destination index 0 — don't assume `>>` is always "the right one." Trace with a small example (`16'h1234` → `{>>{a}}` gives `b[0]=8'h12`) if unsure.
- Queue → dynamic array is a **legal direct assignment**, no loop/cast needed, if element types match.

### Functions
- Function return type can't be a variable name — needs an actual type or `typedef`.

---

## 2. Procedural Routines — Functions, Tasks, Lifetime

- **Function = zero-simulation-time execution.** No `#`, `@`, blocking `wait`, or blocking `fork...join` — must execute and return within the same time step it was called.
- **Default lifetime rule** ⚠️ (easy to tangle): **module-scope tasks/functions → `static` by default. Class methods → `automatic` by default.** This asymmetry is why module-level helper tasks are a common source of fork/race bugs, while class-based UVM code is usually safe by default.
- **`ref` requires automatic lifetime** — not because of module-variable visibility, but because the *ref-binding itself* needs a fresh stack frame per call; a static task would let concurrent calls clobber each other's binding.
- **`const ref`**: zero-copy alias (same performance benefit as `ref`), compiler-enforced **read-only**. ⚠️ NOT "modifies locally but doesn't propagate" — there's no copy at all, ever; the compiler just blocks writes. Good for scoreboard/checker functions holding large reference data.
- **Classic bug — static local + fork loop**: a module-scope task with a `static` local variable, forked from a `for` loop, has ALL forked calls share one memory location → last call's value silently overwrites everything, all iterations print the same (wrong) final value.
- **Fork-capture idiom** ⚠️ (tripped up twice): any per-iteration value used inside a `fork` block must be **declared automatic AND explicitly assigned** from the loop variable, inside the fork block itself:
  ```systemverilog
  fork
    automatic int idx = i;   // must assign, not just declare
    do_something(idx);
  join_none
  ```
  Declaring `automatic int idx;` alone (no assignment) does NOT inherit the outer loop's current value — defaults to 0.
- **Mixed lifetime**: an `automatic` task can still have specific `static` locals for a deliberate cumulative/shared counter — legitimate pattern, just must be intentional, not accidental (forgetting the task's own `automatic` keyword).

---

## 3. OOP — Inheritance, Polymorphism, Copy Semantics

### Virtual Dispatch
- **Non-virtual method calls resolve by the class where the CALLING CODE is textually written** (static binding).
- **Virtual method calls resolve by the ACTUAL RUNTIME object type**, regardless of where the calling code lives (dynamic binding) — this holds even when the call happens *inside another base-class method* (the "template method" pattern).

### Data Member Hiding (distinct from method overriding!)
- ⚠️ **Member variables are NEVER polymorphic** — always resolved by the class where the *accessing code* lives (same rule as non-virtual methods), regardless of whether the method itself is virtual.
- If base and derived both declare a field with the same name, they are **two separate memory locations** (shadowing, not overriding) — both coexist in the object.
- Trap: a virtual method defined in `base` that references `data` will read `base::data`, NOT `derived::data`, even when dynamically dispatched to run in a `derived`-context call chain.
- **Good practice**: avoid same-name shadowed fields entirely — use distinct names, or don't redeclare the field in the derived class at all.

### Constructor Order Gotcha ⚠️ (genuinely important, LRM-guaranteed, not a race)
Sequence when `derived::new()` calls `super.new()`:
1. `super.new()` (base constructor body) runs **completely first** — including any virtual method calls it makes.
2. **Only after** `super.new()` returns do derived's own inline field initializers run.
3. Rest of derived's constructor body executes.

**Consequence**: if a virtual method is called from inside the base constructor, and the actual object is `derived`, the call correctly dispatches to `derived`'s override — but that override will see derived's own fields still at **default values (0)**, since step 2 hasn't happened yet. This is 100% reproducible, not a race. **Rule of thumb: never call virtual methods from constructors.**

### Abstract Classes
- `virtual class` = cannot be instantiated, only extended (different meaning of "virtual" than `virtual function` — dispatch vs. instantiation restriction).
- `pure virtual function` = **no implementation anywhere in the base** — just a signature/contract.
- A subclass that doesn't implement a required pure virtual method **compiles fine** (class declaration itself is fine) — error only occurs when you try to **instantiate** that subclass (`new()`).
- Real UVM tie-ins: `uvm_sequence_base` (body() task), base transaction classes (convert2string/do_compare/do_copy contracts), base checker classes across similar sub-blocks.

### `$cast` / Static Cast
- **"Going up is free, going down needs proof."** Upcast (derived→base) always legal/automatic. Downcast (base→derived) needs `$cast` (or unsafe static cast).
- Direction (up/down) is determined **purely by declared handle types** (compile-time). Success/failure of a downcast depends on the **object's actual permanent runtime type** (checked live).
- `$cast(dest, src)` fails **safely**: returns 0, leaves `dest` completely unchanged. No crash by itself.
- **Static cast** (`type'(expr)`) on an incompatible object: **no runtime check at all** — silently "succeeds," assigning a mismatched handle. Danger is **deferred** — breaks unpredictably whenever the mistyped handle is later used (accessed field/method that doesn't really exist on the actual object). This is why `$cast` is always preferred for class-handle downcasting.

### Static Class Members
- `static` on a **class property** = one shared memory location across ALL instances (different axis entirely from static/automatic **lifetime** of task/function locals).
- Static methods have **no `this`** — that's *why* they can't access non-static (instance) members, not because of any restriction on local variable types inside them.
- Accessing a static property through an object handle (`obj.static_field`) is legal and refers to the exact same shared memory as `ClassName::static_field`.

### Shallow vs Deep Copy
- Shallow copy: copies the outer object but just **reassigns the nested object's handle** — both copies end up sharing the same nested memory. Modifying one's nested field affects the other.
- Deep copy: constructs a **new** nested object and copies values into it — fully independent afterward.
- ⚠️ **Corruption from an earlier shallow copy persists** even after later switching to a properly-implemented deep copy elsewhere in the code — the deep copy doesn't retroactively fix already-corrupted shared state from before.
- UVM's default `copy()`/`clone()` does field-by-field copying for **built-in types**, but for any **nested object handle** member, you must implement `do_copy()` yourself (or use `` `uvm_field_object ``) — otherwise you get the exact shallow-copy bug. Real risk: a scoreboard "snapshotting" a transaction via shallow clone, then the original transaction's nested object gets mutated later — silently corrupting the "saved" snapshot too.

---

## 4. Concurrency — fork-join, Semaphores, Mailboxes, Events

- **`join`**: wait for ALL forked processes. **`join_any`**: wait for at least one; others continue in background (NOT killed). **`join_none`**: don't wait at all.
- **`disable fork`**: kills all still-active child processes spawned by the *current* process's fork — standard pairing with `join_any` for timeout-vs-response race patterns.
- **Semaphore vs Mailbox — the core distinction**:
  - **Semaphore**: manages **permission/access** to a limited resource. No payload — just a count of available "keys." (Traffic light analogy.)
  - **Mailbox**: a **FIFO queue** that carries actual **data/payload** between processes, with built-in blocking (`get()` blocks if empty, `put()` blocks if full/bounded). (Delivery truck analogy.)
  - Mailbox = queue + automatic inter-process blocking synchronization, so you don't hand-roll your own polling/event logic.
  - Bounded (`new(1)`) vs unbounded (`new()`) mailbox: only produces different behavior when **producer and consumer rates differ** — if consumer is always faster/keeping pace, bounding to 1 changes nothing observably.
  - UVM tie-in: `seq_item_port`/`seq_item_export` and `uvm_tlm_analysis_fifo` are built on exactly this mailbox-style blocking data-passing mechanism.
- **Events**: ⚠️ **non-persistent, momentary** — a trigger (`->`) only wakes processes **already blocked and waiting at that exact instant**. If nobody is waiting yet when it fires, the trigger is lost forever — the waiter (if it starts listening later) will block indefinitely.
  - `.triggered` is true only **during the same simulation time step** the trigger fired — does NOT mean "did this ever happen in the past."
  - To handle "might have already happened" semantics, pair the event with a **persistent flag/variable** and check the flag before waiting.
  - **Semaphore = persistent state** (late arrivals still correctly served) vs **Event = transient occurrence** (late "arrivals" miss it entirely) — this is why they solve fundamentally different problems and aren't interchangeable.

---

## 5. Randomization & Constraints

- **`rand` vs `randc`**: `randc` guarantees no-repeat-until-exhausted, but **only per-object** (not across different object instances) — and is practically limited to **small bit widths (~4-8 bits)** since the tool must store/permute the entire value range.
- **Causes of `randomize()` returning 0** (beyond simple contradicting constraints): `solve...before` ordering combined with an impossible dependent constraint; contradictory array-size/foreach constraints; `rand_mode(0)` combined with an active constraint the frozen value doesn't satisfy; solver complexity/timeout on very large systems.
- **Constraint inheritance**: default is **ANDed** across all levels (base + derived, all active hard constraints must be simultaneously satisfiable).
- **Enabling derived-class overrides of a base constraint** — three real mechanisms:
  1. Mark the **base** constraint `soft` (⚠️ not the derived one) — any derived hard constraint then simply wins.
  2. Redeclare a constraint block with the **same name** in the derived class — this **fully replaces** (not ANDs with) the base version.
  3. `constraint_name.constraint_mode(0)` — explicitly disables an inherited constraint, typically called in the derived class's `new()`.
- ⚠️ **`rand_mode()` controls a VARIABLE on/off. `constraint_mode()` controls a CONSTRAINT BLOCK on/off.** These get mixed up constantly.
- **`dist` operator**: `:=` assigns the **same weight to each individual value** in a range. `:/` **divides the total weight** across the values in the range.
- ⚠️ **`solve...before` affects distribution/probability ONLY — never legality.** The solver always produces a constraint-legal result regardless of solve order; `solve X before Y` only changes how uniformly values get distributed across branches/combinations.
- **Inline constraints** (`randomize() with {...}`) are **hard by default**, and override in-class `soft` constraints. Inline `soft` vs. class-level `soft`: inline still wins (inline constraints take precedence at matching strength — hard-vs-hard or soft-vs-soft — this is a defined LRM rule, not solver-arbitrary).
- A hard `dist` constraint and an inline hard override **don't conflict** as long as the inline value is still within the `dist`'s legal set.
- `pre_randomize()`/`post_randomize()`: printing "stale" pre-randomization values is a genuine debugging technique — helps catch bugs where an object isn't actually being re-randomized as expected (e.g., broken clone/copy logic).
- `unique {array}` + full-range coverage with exactly N elements over N legal values → the **set** of values is fully deterministic, only the **assignment/permutation** is random.
- **Debugging over-constrained failures**: (1) read the solver's failure log (most common/practical — usually names the conflicting constraints), (2) selectively disable constraints via `constraint_mode(0)` and bisect to isolate the culprit in large/deep hierarchies.

---

## 6. SVA (SystemVerilog Assertions)

- **`|->` (overlapped)**: consequent checked on the **same** clock edge as the antecedent. **`|=>` (non-overlapped)**: consequent checked on the **next** clock edge.
- **Sampling functions** (`$stable`, `$rose`, `$fell`, `$past`) only ever compare **values sampled at clock edges** — ⚠️ they are **blind to anything that happens between edges** (a mid-cycle glitch that resolves back to the same value by the next edge is invisible to them).
  - `$rose(sig)` ≡ current sample = 1 AND previous sample = 0. First-cycle edge case: no "previous" sample exists — tool-dependent, common source of spurious behavior at time 0 — guard with `disable iff` during reset.
  - `$past(sig, N)`: N cycles back; default N=1.
- **`throughout` / `within` / `intersect`** — commonly blurred, precise definitions:
  - **`throughout`**: `boolean throughout sequence` — the boolean must hold **true on every single cycle** across the sequence's span (persistent, continuous claim).
  - **`within`**: `seq1 within seq2` — seq1's entire match (start AND end) must be **nested inside** seq2's match window (a containment/boundary check, not "true somewhere in there").
  - **`intersect`**: `seq1 intersect seq2` — both sequences must match with the **exact same start cycle AND exact same end cycle** (strict durational alignment) — the strictest of the three.
  - Ranking loosest→strictest: **`within` → `throughout` → `intersect`**.
- **Local variables in sequences**: declared inside a `property`/`sequence`, used to carry a value across a **variable-length gap** (where `$past`'s fixed N won't work, e.g., `##[1:5]`). Comma operator `(req, captured = data)` executes the assignment on the same cycle the match condition is true. Each independent match-attempt gets its **own private copy** — critical for correctly tracking overlapping/pipelined transactions.
- ⚠️ **`disable iff (expr)` doesn't just block NEW evaluations from starting — it immediately ABORTS any already-in-progress evaluation** the moment `expr` becomes true. This is exactly why it's used near-universally: without it, any property mid-check when reset asserts would spuriously fail.
  - Polarity matters: `disable iff (!rst_n)` is correct (disable during reset). `disable iff (rst_n)` (inverted) would disable during normal operation and only check during reset — a silent, dangerous "always passes" bug.
  - Safe to use with an asynchronous reset signal — SVA's disable mechanism is specifically designed to handle this by continuous sampling, not a metastability risk in the way async RTL logic would be.
- **`assert` vs `cover` vs `assume`**:
  - `assert property`: checks, flags failure.
  - `cover property`: just records whether/how often a scenario occurred — no pass/fail.
  - `assume property`: in **simulation**, behaves essentially like `assert` (just checks). In **formal verification**, it instead **constrains the solver's input search space** — a fundamentally different purpose. ⚠️ A wrong/overly-restrictive `assume` in formal can cause the tool to falsely "prove" an assertion that would actually fail under excluded (but legal) input sequences.
- **Multi-clock assertions**: `@(clk_a) seq1 ##0 @(clk_b) seq2` — the `##0` here is a **domain-transition marker**, not "same simulation time."
  - In practice, **real CDC handshake verification is NOT done via one sprawling multi-clock property** — synchronizer latency is inherently variable by design, so no fixed timing relationship could be correctly asserted. Real CDC verification uses **dedicated static/structural CDC tools** (Questa CDC, SpyGlass CDC) checking topology (no combinational logic between synchronizer flops, proper Gray-coding for multi-bit crossings, etc.) — a fundamentally different, non-simulation-based methodology.
  - `$past`/`$rose`/etc. are meaningless when applied to a signal from a *different* clock domain than the property's own sampling clock.

### Metastability & Synchronizers (RTL background for CDC)
- Metastability: a flop's data input changes within its setup/hold window → output may take a long time to settle, or briefly sit at an invalid analog level.
- 2-flop synchronizer: FF1 (may go metastable) is given **one full receiving-clock period** to settle before FF2 samples it — this is *why* synchronizers inherently add 1-2 cycles of latency (a necessary feature, not a bug to assert against).
- **Zero combinational logic allowed between the two synchronizer flops** — combinational logic can't reliably process a still-settling/metastable input, and can itself introduce glitches. This structural rule is exactly what static CDC tools check for.

---

## 7. Functional Coverage

- `bins name[] = {range}` → **explodes into one bin per individual value** in the range, each independently tracked/hit-counted.
- `bins name = {range}` (no brackets) → **one aggregate bin**, hit if *any* value in the range occurs (no per-value granularity).
- A coverpoint with **no explicit bins** → SV **auto-creates one bin per possible value** (e.g., 256 bins for an 8-bit field) — coverage IS reported by default. Practical concern: 256 individual bins can be slow to close and aren't very informative — real code usually explicitly buckets into meaningful ranges instead.
- Coverage sampling is tied to a **semantic event** (transaction completion via monitor→subscriber `write()` callback), not raw clock ticks.
- ⚠️ **Coverage % is "hit at least once" per bin (binary), NOT a frequency/weighted metric.** Hitting a bin 40 times contributes the same as hitting it once — unless `option.at_least` is raised.
- `illegal_bins`: triggers a **runtime error** if hit. `ignore_bins`: **silently excluded** from coverage accounting (doesn't need to be hit for 100%).
- Cross coverage: total bins = product of legal bins in each crossed coverpoint. `illegal_bins` auto-excluded from a cross by default; `ignore_bins` exclusion may need to be made **explicit within the cross itself** for reliability.
- Transition bins: `(0=>1)` requires a **direct, single-step** transition — no intervening values allowed. `(0,1,2=>2)` is shorthand for `(0=>2) OR (1=>2) OR (2=>2)` — multiple possible starting points, one shared destination, NOT one linear sequence.
- `option.at_least`: minimum hits before a bin counts as covered (default 1).
- `option.goal`: target coverage % for "done" status (default 100) — a separate knob from `at_least`, purely a reporting/pass-fail threshold.
- ⚠️ **Coverage credited regardless of pass/fail risks a false sense of completeness** — a scenario can be "covered" while the DUT actually behaved incorrectly when it occurred. Best practice: correlate coverage sampling with correctness (e.g., exclude failed/mismatched transactions), or track pass/fail-correlated coverage separately.
- Parameterized covergroups (`covergroup cg(int max_val); ... endgroup`) — useful for reusing one coverage model across multiple instances/configurations of similar sub-blocks with different runtime parameters.

---

## 8. UVM

### Factory Mechanics
- `type_id::create()` internally: (1) checks the override table for the requested type, (2) constructs the actual (possibly overridden) object, (3) performs an **upcast `$cast`** into the **originally requested/declared type** to hand back to the caller.
- ⚠️ **This internal cast goes INTO the requested type, NOT into the overridden type.** The declared-type-governs-method-access rule applies identically here: a handle declared `base_driver` (even holding a real `fast_driver` underneath via override) **cannot** call `fast_driver`-specific methods without an explicit, separate downcast `$cast`. Factory overrides are transparent precisely because the calling code never needs to know an override happened.
- `` `uvm_component_utils(ClassName) `` generates: `get_type()` (type wrapper for factory lookups), `get_type_name()`, an internal `create()` method, and registers the class into the factory's global type database.
- If the **override target** class forgot this macro, `ClassName::get_type()` **fails to compile** (undefined method) — a compile-time error, not a runtime one.

### `$cast` Quick Rules (see also OOP section)
- Direction (up/down) = purely declared handle types (compile-time). Success = actual/permanent runtime object type (checked live).
- "Going up is free, going down needs proof."
- `$cast` fails safely (returns 0, destination untouched). Static cast on mismatch fails silently/dangerously (assigns anyway, breaks later, unpredictably, whenever the mistyped handle is used).

### Phase Ordering
- `build_phase`: **top-down** — but each level's `build_phase` function body **completes and returns** before the phase engine automatically invokes the next (child's) `build_phase` — it's not literally called from within the parent's code.
- `connect_phase`: **bottom-up**, and only begins after **every** component's `build_phase` across the entire hierarchy has completed — necessary because TLM ports are typically constructed during their owning component's own `build_phase`, so connecting them earlier risks a not-yet-constructed port.
- ⚠️ **ALL `build_phase` calls across the entire testbench happen at exactly `$time == 0`**, always — since `build_phase` is a `function` (zero-simulation-time rule). No sibling component's build_phase can occur at a different simulation time than another's.
- Run-time phase family (`reset_phase`, `configure_phase`, `main_phase`, `shutdown_phase`, etc.) exists to provide **structured, hierarchy-wide synchronization checkpoints** between phases, without hand-rolling cross-component sync logic inside one giant `run_phase`.

### TLM Ports
- `seq_item_port.get_next_item(tr)`: blocking, mailbox-like — waits for the sequencer to hand over an item after arbitration.
- `get_next_item()` / `item_done()` two-step pattern exists because **driving takes real simulation time** — the sequence needs an explicit "driver has finished" signal, not just "driver received it."
- ⚠️ **`uvm_analysis_port` is ONE-TO-MANY (broadcast)** — a single `.write()` call delivers to every connected subscriber. **`seq_item_port`/`seq_item_export` is STRICT ONE-TO-ONE.** (Easy to get this backwards.)
- `ap.write(tr)` delivers the **same object handle** to every connected subscriber — not independent copies. Direct tie to the shallow-copy risk: if a monitor reuses/overwrites the same `tr` object across transactions, and a subscriber stores/queues the handle without cloning, later comparisons can silently use corrupted/overwritten data.

### Sequences & Virtual Sequences
- `start_item(tr)`: **blocking arbitration request** — waits for the sequencer's arbiter to grant this sequence the right to send.
- `randomize()` deliberately called **between** `start_item()` and `finish_item()` — only randomize after arbitration is won (avoid wasted randomization on items that might lose arbitration), using the freshest possible context right before commit.
- `finish_item(tr)`: sends the item to the driver via the sequencer's FIFO, blocks until `item_done()`.
- **Virtual sequences** don't drive any interface themselves — they orchestrate/coordinate multiple lower-level sequences across multiple (possibly unrelated) sequencers. Parameterized on generic `uvm_sequence_item` since they have no transactions of their own.
- **`p_sequencer` / `` `uvm_declare_p_sequencer ``**: every sequence automatically has `m_sequencer` (a generic `uvm_sequencer_base` handle, set by `.start()`) — but this generic handle **can't see derived-class-specific members** (e.g., `agentA_seqr`) due to the exact same declared-type-governs-access rule as the classic `animal`/`dog` `$cast` problem. The macro auto-generates a properly-typed `p_sequencer` member and auto-performs the `$cast` from `m_sequencer` — pure boilerplate-avoidance for a downcast every virtual sequence needs. (The manual alternative — declaring the handle directly and wiring it from the test — works but requires repeated manual wiring per test/call-site and risks silent null-handle bugs if forgotten.)
- `.start()` on a sub-sequence from within a virtual sequence's `body()` is **blocking/sequential by default** — need an explicit `fork...join` to run sub-sequences concurrently.

---

## Topics Not Yet Covered (remaining, lower priority)
- SVA: sequence `and`/`or`/`first_match`, assertion `bind`, severity/debug control
- SV scheduling semantics (event regions: Active/Inactive/NBA/Observed/Reactive/Postponed)
- Coding brainteasers: CDC synchronizers, async FIFO design, round-robin arbiter
- UVM: component architecture deep-dive, `config_db` patterns, `uvm_reg` (if relevant to role)
