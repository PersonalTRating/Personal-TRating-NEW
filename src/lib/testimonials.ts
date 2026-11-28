// Real, consented testimonials shown across the platform (homepage and /for-trainers).
// Quotes are word for word as supplied. Do not edit them.

export interface Testimonial {
  kind: 'client' | 'trainer';
  name: string;
  info: string;
  initials: string;
  bg: string;
  color: string;
  href?: string;
  text: string;
}

export const clientTestimonials: Testimonial[] = [
  { kind: 'client', initials: 'L', bg: '#eaf7ec', color: '#2a9438',
    name: 'Lauren', info: 'Verified client',
    text: '"The ad on the website is kinda what I was like on my first day at the gym. I had anxiety and everyone around seemed to know what they were doing. CoachCards allowed me to find a trainer who I wasn\'t nervous to meet as I could check their reviews. I met a great trainer and have never looked back."' },
  { kind: 'client', initials: 'J', bg: '#e8f0f7', color: '#1a4b6b',
    name: 'Josh', info: 'Client',
    text: '"I came across loads of trainers online when I was trying to find one to level up my fitness game. They all seemed to claim they were great so I didn\'t know how to judge them. I ended up finding one on CoachCards with a good BMP and reviews so went with that one."' },
];

export const trainerTestimonials: Testimonial[] = [
  { kind: 'trainer', initials: 'T', bg: '#fdf6e3', color: '#b8860b',
    name: 'Tracy', info: 'Personal Trainer · London',
    href: '/trainers/ed71661a-2515-4df0-b0fe-0f486968d104',
    text: '"I\'ve been a personal trainer for 3 years now and have built up a bit of a client base. You do often find however that after you\'ve shown someone the ropes they move on to training themselves. This is natural but CoachCards gave me a platform for them to pass on their experience with me to potential new clients. This has been great for my business."' },
  { kind: 'trainer', initials: 'P', bg: '#f5e8f7', color: '#6b1a6b',
    name: 'Paul', info: 'Personal Trainer · London',
    href: '/trainers/639b7020-9f0a-4ff4-b352-8169d1d65068',
    text: '"I am always looking for ways to keep myself accountable and through this make my coaching the best it can be. Using CoachCards I\'ve started asking my clients for a review, with no hint that it should be positive. This gives me a great source of feedback, if there\'s something I\'m doing wrong I can address it. I work to make all reviews positive and if they are the public will see what I can offer."' },
];
