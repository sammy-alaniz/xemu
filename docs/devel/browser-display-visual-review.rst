Browser display visual review
=============================

The browser display work should be judged by human visual review, not by exact
frame matching. Native xemu, native software GL, and browser WebGL can run at
different speeds. That makes frame number, wall-clock time, pixel hashes, and
pixel diffs too brittle for this stage of the work.

The useful question is qualitative: does the browser output move through the
same broad visual states as native xemu, in the same order, with fewer black
gaps, fewer corrupt colors, better proportions, and the same final screen?

Capture policy
--------------

Capture boring evidence automatically. Judge the evidence manually.

The standard capture rate is 2 frames per second. A capture should start when
xemu starts and run long enough to include the final
``Please insert an Xbox disc...`` screen. The duration is intentionally a knob,
because native and browser timing can differ.

Do not use scripts that produce pass/fail scores for the frames. A review page
or contact sheet is fine. Pixel diffs, image hashes, and exact frame-number
matching are not the decision maker for this branch.

Native software GL reference
----------------------------

Use software GL for native reference captures on this host. Hardware GL wedged
the AMD GPU during testing, while llvmpipe produced a normal xemu screenshot.

The checked-in golden native strip lives at:

.. code-block:: text

   docs/devel/browser-display-golden/native-llvmpipe-insert-disc-boot/

This strip is the current ideal reference for the no-disc boot flow. It shows
the black startup frames, the green Xbox boot animation, the clean Xbox logo,
and the final ``Please insert an Xbox disc...`` screen.

Start native xemu with software GL:

.. code-block:: sh

   ./scripts/start-native-software-gl.sh

Capture a native boot strip:

.. code-block:: sh

   ./scripts/capture-native-boot-strip.sh --seconds 35 --fps 2

The script prints the output directory when it finishes. The directory contains
numbered PNG files, ``native-xemu.log``, and ``manifest.json``.

The native capture uses xemu's own screenshot path. It sets the internal
``g_screenshot_pending`` flag in the running xemu process, so the PNGs come
from the same screenshot helper normal desktop xemu uses.

Browser strip
-------------

Capture a browser boot strip:

.. code-block:: sh

   ./scripts/capture-browser-boot-strip.mjs --seconds 45 --fps 2

The browser script starts the local asset server, starts Firefox through
WebDriver BiDi, runs the browser boot page in interactive mode, and saves the
visible browser display canvas as numbered PNGs. It also saves
``transcript.txt`` and ``manifest.json``.

Use ``--build-dir`` when testing a non-default wasm build:

.. code-block:: sh

   ./scripts/capture-browser-boot-strip.mjs --build-dir ../../build-wasm --seconds 45 --fps 2

Review page
-----------

Build an HTML review page from one or both strips:

.. code-block:: sh

   ./scripts/make-boot-strip-review-page.py \
     --native docs/devel/browser-display-golden/native-llvmpipe-insert-disc-boot \
     --browser /tmp/xemu-boot-strips/browser-YYYYMMDD-HHMMSS \
     --out /tmp/xemu-boot-strip-review.html

Open the generated HTML file and review it visually. The page deliberately
does not compute hashes, diffs, similarity scores, or pass/fail results.

What to look for
----------------

Look for whether the browser gets closer to native in the way a person would
describe the boot animation:

* the same broad ordering of black screen, animation frames, and final screen
* fewer long black gaps after visible output starts
* fewer scrambled color bands or obviously wrong texture layouts
* better aspect ratio and placement
* a final screen that visually matches native xemu

This is intentionally subjective. At this stage, subjective visual judgment is
more useful than a fragile exactness metric.
