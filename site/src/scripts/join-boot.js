/* Wires the waitlist form. main.js imports this first, so the form works even if the
   animation code that follows throws while it loads. Nothing here needs GSAP or the page
   kit; the success animation checks for window.gsap itself. */
import { setupJoin } from './waitlist.js';

setupJoin();
