import React, {useEffect, useState} from 'react';
import {Button, useApp} from './core.jsx';

// This presentation intentionally separates implemented example workflows from
// future Unity integration. Adjust the wording to match the delivered build.
const chapters = [
  {
    "id": "intro",
    "section": "01 / Project overview",
    "title": "Firstlight Online",
    "subtitle": "A companion website for Revive",
    "body": "Revive is a multiplayer extraction game set around a safe colony inside a black hole. Firstlight Online gives that world an online home for its players.",
    "points": [
      "The game creates the expeditions.",
      "The website supports the player between expeditions."
    ]
  },
  {
    "id": "background",
    "section": "02 / Background",
    "title": "Why this project exists",
    "subtitle": "The world does not have to stop when the game closes.",
    "body": "In Revive, players prepare for expeditions, collect items, and return to Firstlight Colony. That raised a design question: what parts of a player's life in this world should remain available outside a game session?",
    "points": [
      "A shared account is the foundation.",
      "Inventory, messages, shops and services can live beyond a single mission."
    ]
  },
  {
    "id": "importance",
    "section": "03 / Importance",
    "title": "Function before spectacle",
    "subtitle": "A beautiful interface matters. A useful one matters more.",
    "body": "The goal is not only to look like an extension of the game. It is to make persistent player information and everyday services understandable, safe, and genuinely usable.",
    "points": [
      "Keep the player's account and possessions organized.",
      "Give meaningful actions clear feedback and accurate records.",
      "Build toward a future connection with the Unity game."
    ]
  },
  {
    "id": "scope",
    "section": "04 / Original scope",
    "title": "The ambition was bigger than the calendar",
    "subtitle": "I planned an entire connected player ecosystem.",
    "body": "The original vision included account identity, inventory, Chroma currency, shops, deliveries, housing, messaging, gifting, equipment care, rewards and deeper Unity integration, along with a distinctive visual experience.",
    "points": [
      "That was too much to fully complete and verify in the available timeframe.",
      "I narrowed my priority to functional, demonstrable website workflows.",
      "Unfinished game integration and wider features remain future work."
    ]
  },
  {
    "id": "challenges",
    "section": "05 / Challenges",
    "title": "Where I struggled",
    "subtitle": "The hardest choices were often about priorities.",
    "body": "The biggest struggle was balancing an ambitious creative direction against the effort required to build reliable systems. Visual redesigns consumed time that also needed to go toward validating real behavior.",
    "points": [
      "Scope kept expanding faster than implementation time.",
      "Making interfaces attractive and functional took different kinds of work.",
      "Sample flows, saved accounts, and Unity integration had to be kept distinct."
    ]
  },
  {
    "id": "highlights",
    "section": "06 / Milestones",
    "title": "The moments that made it feel real",
    "subtitle": "Individual pages began working together.",
    "body": "The strongest milestone was moving beyond isolated screens toward connected player services: browsing supplies, reviewing a purchase, seeing a Chroma change and finding a corresponding notice in Mail.",
    "points": [
      "Account identity and inventory workflows have real backend foundations.",
      "Shops include an interactive, isolated example purchase flow.",
      "Mail, housing, messaging and other services give the colony a larger shape."
    ]
  },
  {
    "id": "status",
    "section": "07 / Current result",
    "title": "What I can show today",
    "subtitle": "A working foundation, not a finished game.",
    "body": "The React project contains navigable player services, example-mode interactions, and backend-connected workflows documented in the project. Some end-to-end production interactions still need signed-in verification, and Unity-side integration is not complete.",
    "points": [
      "The demonstration uses clearly labeled example data.",
      "Sample shop purchases and Mail notices can be tested without spending real Chroma.",
      "Sample Inventory is a separate workspace, not a direct mirror of example purchases."
    ]
  },
  {
    "id": "demo",
    "section": "08 / Live demonstration",
    "title": "Let the website speak for itself",
    "subtitle": "A short walkthrough of the parts that work.",
    "body": "I will start with the example shop experience, show how a purchase moves into Mail, and then explore Inventory and the account workspace. These are example-mode flows for a safe classroom demonstration.",
    "points": [
      "1. Browse Hyphen Surplus and review an example purchase.",
      "2. Open Mail to look for the matching delivery notice.",
      "3. Open Inventory and the account area to show the wider service structure."
    ]
  }
];

const clampChapter = index => Math.max(0, Math.min(index, chapters.length - 1));

export function Presentation() {
  const {chapter: requestedChapter} = useApp();
  const [index, setIndex] = useState(() => {
    const requested = chapters.findIndex(item => item.id === requestedChapter);
    return clampChapter(requested < 0 ? 0 : requested);
  });
  const chapter = chapters[index];
  const isLast = index === chapters.length - 1;

  useEffect(() => {
    function handleKeys(event) {
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      if (event.target?.closest?.('nav, input, textarea, select, [contenteditable], dialog, a, button')) return;
      const changes = {ArrowLeft: -1, ArrowRight: 1};
      if (event.key in changes) {
        event.preventDefault();
        setIndex(current => clampChapter(current + changes[event.key]));
      }
      if (event.key === 'Home') {event.preventDefault();setIndex(0);}
      if (event.key === 'End') {event.preventDefault();setIndex(chapters.length - 1);}
    }
    document.addEventListener('keydown', handleKeys);
    return () => document.removeEventListener('keydown', handleKeys);
  }, []);

  return <section className="presentation-interface" aria-label="Capstone presentation">
    <div className="presentation-stage">
      <div className="presentation-topline">
        <span className="presentation-brand">FIRSTLIGHT / CAPSTONE</span>
        <span className="chapter-position" aria-live="polite">{String(index + 1).padStart(2, '0')} / {String(chapters.length).padStart(2, '0')}</span>
      </div>
      <div className="presentation-progress" role="progressbar" aria-label="Presentation progress" aria-valuenow={index+1} aria-valuemin={1} aria-valuemax={chapters.length}>
        <span style={{width:((index+1)/chapters.length*100)+'%'}} />
      </div>
      <div className="presentation-copy" aria-live="polite" aria-atomic="true">
        <div key={chapter.id} className="chapter-content">
          <p className="presentation-eyebrow">{chapter.section}</p>
          <h2>{chapter.title}</h2>
          <p className="presentation-subtitle">{chapter.subtitle}</p>
          <p className="presentation-body">{chapter.body}</p>
          <ul className="presentation-points">
            {chapter.points.map(item => <li key={item}>{item}</li>)}
          </ul>
          {isLast && <div className="presentation-demo">
            <p className="presentation-demo-label">Open example workflows in separate tabs</p>
            <div className="presentation-demo-links">
              <a href="/shops.html?mode=sample&shop=hyphen&journey=delivery" target="_blank" rel="noopener noreferrer">Shop + order</a>
              <a href="/mail.html?mode=sample" target="_blank" rel="noopener noreferrer">Mail</a>
              <a href="/inventory.html?mode=sample" target="_blank" rel="noopener noreferrer">Inventory</a>
              <a href="/index.html?mode=sample" target="_blank" rel="noopener noreferrer">Account</a>
            </div>
          </div>}
        </div>
      </div>
      <div className="presentation-controls">
        <Button disabled={index === 0} onClick={() => setIndex(current => clampChapter(current - 1))}>Previous</Button>
        <div className="chapter-picker" role="group" aria-label="Presentation chapters">
          {chapters.map(({id, title}, destination) => <button
            key={id}
            type="button"
            className="chapter-dot"
            title={title}
            aria-label={'Go to '+title}
            aria-pressed={index === destination}
            onClick={() => setIndex(destination)}
          />)}
        </div>
        <Button variant="primary" onClick={() => setIndex(current => isLast ? 0 : clampChapter(current + 1))}>{isLast ? 'Restart' : 'Next'}</Button>
      </div>
      <p className="presentation-tip">Use the arrow keys to advance. Demo links open separately so this slide stays in place.</p>
    </div>
  </section>;
}
