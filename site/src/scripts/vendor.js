/* GSAP from npm, exposed as globals for the motion kit and the page scripts. */
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { ScrollSmoother } from 'gsap/ScrollSmoother';
import { SplitText } from 'gsap/SplitText';
import { CustomEase } from 'gsap/CustomEase';

Object.assign(window, { gsap, ScrollTrigger, ScrollSmoother, SplitText, CustomEase });
