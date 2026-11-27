/* Load order matters: the waitlist form first, so it works even if the motion code throws,
   then GSAP globals, example data, replicas, motion kit, then the page. */
import './join-boot.js';
import './vendor.js';
import './story.js';
import './body.js';
import './app.js';
import './demo.js';
import './kit.js';
import './beats.js';
import './page.js';
import './extras.js';
