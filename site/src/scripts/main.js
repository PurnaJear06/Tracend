/* Load order matters: GSAP globals, example data, replicas, motion kit, then the page. */
import './vendor.js';
import './story.js';
import './body.js';
import './app.js';
import './demo.js';
import './kit.js';
import './beats.js';
import './page.js';
import { setupJoin } from './waitlist.js';

setupJoin();
