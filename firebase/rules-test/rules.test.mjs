// Security rules tests for friends and trip rooms. Run against the local emulator only:
//   npm install && npm run emulate
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import {
  arrayRemove, arrayUnion, deleteDoc, deleteField, doc, getDoc, runTransaction, serverTimestamp, setDoc, Timestamp, updateDoc, writeBatch,
} from 'firebase/firestore';

let env;
const A = 'alexUid', M = 'minaUid', K = 'kenUid';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-travelcopilot',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  // Seed: three people with IDs; Alex and Mina are friends; Ken is not.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, h, n] of [[A, 'alex_k', 'Alex'], [M, 'mina', 'Mina'], [K, 'kenji', 'Ken']]) {
      await setDoc(doc(db, 'handles', h), { uid, name: n });
      await setDoc(doc(db, 'users', uid), { handle: h, name: n, createdAt: Timestamp.now() });
    }
    await setDoc(doc(db, 'users', A, 'friends', M), { handle: 'mina', name: 'Mina', since: Timestamp.now(), via: 'seed' });
    await setDoc(doc(db, 'users', M, 'friends', A), { handle: 'alex_k', name: 'Alex', since: Timestamp.now(), via: 'seed' });
    await setDoc(doc(db, 'rooms', 'r1'), {
      name: 'Tokyo trip', owner: A, memberIds: [A], friendsCanEdit: true, createdAt: Timestamp.now(),
      members: { [A]: { name: 'Alex', handle: 'alex_k', role: 'owner' } },
    });
  });
});

const as = (uid) => env.authenticatedContext(uid).firestore();

test('a taken @ID cannot be claimed', async () => {
  const db = as(K);
  await assertFails(runTransaction(db, async (tx) => {
    tx.set(doc(db, 'handles', 'mina'), { uid: K, name: 'Ken' });
    tx.set(doc(db, 'users', K), { handle: 'mina', name: 'Ken', createdAt: serverTimestamp() }, { merge: true });
  }));
});

test('a free @ID can be claimed with the user doc', async () => {
  const db = as(K);
  await assertSucceeds(runTransaction(db, async (tx) => {
    tx.delete(doc(db, 'handles', 'kenji'));
    tx.set(doc(db, 'handles', 'ken_new'), { uid: K, name: 'Ken' });
    tx.set(doc(db, 'users', K), { handle: 'ken_new', name: 'Ken', createdAt: serverTimestamp() }, { merge: true });
  }));
});

test('nobody can list @IDs or read someone else\'s profile or friends', async () => {
  const db = as(K);
  await assertSucceeds(getDoc(doc(db, 'handles', 'mina')));
  await assertFails(getDoc(doc(db, 'users', A)));
  await assertFails(getDoc(doc(db, 'users', A, 'friends', M)));
});

test('a friend request, then accepting it', async () => {
  const ken = as(K);
  await assertSucceeds(setDoc(doc(ken, 'friendRequests', `${K}_${A}`), {
    from: K, to: A, fromHandle: 'kenji', fromName: 'Ken', toHandle: 'alex_k', toName: 'Alex', createdAt: serverTimestamp(),
  }));
  const alex = as(A);
  const b = writeBatch(alex);
  const via = `request:${K}_${A}`;
  b.set(doc(alex, 'users', A, 'friends', K), { handle: 'kenji', name: 'Ken', since: serverTimestamp(), via });
  b.set(doc(alex, 'users', K, 'friends', A), { handle: 'alex_k', name: 'Alex', since: serverTimestamp(), via });
  b.delete(doc(alex, 'friendRequests', `${K}_${A}`));
  await assertSucceeds(b.commit());
});

test('you cannot make yourself someone\'s friend without a request', async () => {
  const ken = as(K);
  await assertFails(setDoc(doc(ken, 'users', A, 'friends', K),
    { handle: 'kenji', name: 'Ken', since: serverTimestamp(), via: `request:${K}_${A}` }));
});

test('a blocked person cannot send a request', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', A, 'blocked', K), { handle: 'kenji', name: 'Ken', since: Timestamp.now() });
  });
  await assertFails(setDoc(doc(as(K), 'friendRequests', `${K}_${A}`), {
    from: K, to: A, fromHandle: 'kenji', fromName: 'Ken', toHandle: 'alex_k', toName: 'Alex', createdAt: serverTimestamp(),
  }));
});

test('redeeming a valid invite makes you friends; an expired one does not', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'invites', 'K7Q4MZ2H'), { owner: A, ownerHandle: 'alex_k', ownerName: 'Alex',
      createdAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() + 86400e3) });
    await setDoc(doc(db, 'invites', 'QXDCDE22'), { owner: A, ownerHandle: 'alex_k', ownerName: 'Alex',
      createdAt: Timestamp.now(), expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  });
  const ken = as(K);
  const pair = (code) => {
    const b = writeBatch(ken);
    b.set(doc(ken, 'users', K, 'friends', A), { handle: 'alex_k', name: 'Alex', since: serverTimestamp(), via: `invite:${code}` });
    b.set(doc(ken, 'users', A, 'friends', K), { handle: 'kenji', name: 'Ken', since: serverTimestamp(), via: `invite:${code}` });
    return b.commit();
  };
  await assertFails(pair('QXDCDE22'));
  await assertSucceeds(pair('K7Q4MZ2H'));
});

test('only friends can be added to a room', async () => {
  const alex = as(A);
  await assertFails(updateDoc(doc(alex, 'rooms', 'r1'), {
    memberIds: arrayUnion(K), [`members.${K}`]: { name: 'Ken', handle: 'kenji', role: 'editor' },
  }));
  await assertSucceeds(updateDoc(doc(alex, 'rooms', 'r1'), {
    memberIds: arrayUnion(M), [`members.${M}`]: { name: 'Mina', handle: 'mina', role: 'editor' },
  }));
});

test('a new member cannot be added as owner', async () => {
  await assertFails(updateDoc(doc(as(A), 'rooms', 'r1'), {
    memberIds: arrayUnion(M), [`members.${M}`]: { name: 'Mina', handle: 'mina', role: 'owner' },
  }));
});

test('non-members cannot read or write a room', async () => {
  const ken = as(K);
  await assertFails(getDoc(doc(ken, 'rooms', 'r1')));
  await assertFails(setDoc(doc(ken, 'rooms', 'r1', 'messages', 'x'),
    { author: K, authorName: 'Ken', text: 'hi', kind: 'text', sentAt: serverTimestamp() }));
});

test('members post messages and can leave', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'rooms', 'r1'), {
      memberIds: arrayUnion(M), [`members.${M}`]: { name: 'Mina', handle: 'mina', role: 'editor' },
    });
  });
  const mina = as(M);
  const b = writeBatch(mina);
  b.set(doc(mina, 'rooms', 'r1', 'messages', 'm1'), { author: M, authorName: 'Mina', text: 'TeamLab Friday?', kind: 'text', sentAt: serverTimestamp() });
  b.update(doc(mina, 'rooms', 'r1'), { lastText: 'Mina: TeamLab Friday?', lastAt: serverTimestamp() });
  await assertSucceeds(b.commit());
  // Can't post as someone else.
  await assertFails(setDoc(doc(mina, 'rooms', 'r1', 'messages', 'm2'),
    { author: A, authorName: 'Alex', text: 'fake', kind: 'text', sentAt: serverTimestamp() }));
  // An editor can't rename the room or take ownership.
  await assertFails(updateDoc(doc(mina, 'rooms', 'r1'), { owner: M }));
  await assertSucceeds(updateDoc(doc(mina, 'rooms', 'r1'), { memberIds: arrayRemove(M), [`members.${M}`]: deleteField() }));
});

test('making a room, with its first system message', async () => {
  const alex = as(A);
  await assertSucceeds(setDoc(doc(alex, 'rooms', 'r2'), {
    name: 'Seoul ideas', owner: A, memberIds: [A], friendsCanEdit: false, createdAt: serverTimestamp(),
    members: { [A]: { name: 'Alex', handle: 'alex_k', role: 'owner' } },
  }));
  await assertSucceeds(setDoc(doc(alex, 'rooms', 'r2', 'messages', 's1'),
    { author: A, authorName: 'Alex', text: 'Alex made this room', kind: 'system', sentAt: serverTimestamp() }));
  // You can't make a room owned by, or already including, someone else.
  await assertFails(setDoc(doc(alex, 'rooms', 'r3'), {
    name: 'x', owner: M, memberIds: [M], friendsCanEdit: true, createdAt: serverTimestamp(),
    members: { [M]: { name: 'Mina', handle: 'mina', role: 'owner' } },
  }));
});

test('making an invite and saving its code on your profile', async () => {
  const alex = as(A);
  const b = writeBatch(alex);
  b.set(doc(alex, 'invites', 'K7Q4MZ2H'), { owner: A, ownerHandle: 'alex_k', ownerName: 'Alex',
    createdAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 7 * 86400e3) });
  b.set(doc(alex, 'users', A), { inviteCode: 'K7Q4MZ2H' }, { merge: true });
  await assertSucceeds(b.commit());
  // Not for someone else, and not for a year.
  await assertFails(setDoc(doc(alex, 'invites', 'Q2Q2Q2Q2'), { owner: M, ownerHandle: 'mina', ownerName: 'Mina',
    createdAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 86400e3) }));
  await assertFails(setDoc(doc(alex, 'invites', 'Q3Q3Q3Q3'), { owner: A, ownerHandle: 'alex_k', ownerName: 'Alex',
    createdAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 365 * 86400e3) }));
});

test('blocking a friend in one batch (requests that may not exist included)', async () => {
  const alex = as(A);
  const b = writeBatch(alex);
  b.set(doc(alex, 'users', A, 'blocked', M), { handle: 'mina', name: 'Mina', since: serverTimestamp() });
  b.delete(doc(alex, 'users', A, 'friends', M));
  b.delete(doc(alex, 'users', M, 'friends', A));
  b.delete(doc(alex, 'friendRequests', `${M}_${A}`));
  b.delete(doc(alex, 'friendRequests', `${A}_${M}`));
  await assertSucceeds(b.commit());
});

test('a member can report a message; a stranger cannot', async () => {
  const report = (db, uid) => setDoc(doc(db, 'reports', `rep-${uid}`), {
    reporter: uid, roomId: 'r1', messageId: 'm1', author: M, text: 'bad', reason: 'Spam or scam', createdAt: serverTimestamp(),
  });
  await assertSucceeds(report(as(A), A));
  await assertFails(report(as(K), K));
  await assertFails(getDoc(doc(as(A), 'reports', `rep-${A}`)));
});

test('Blue replies are posted by the asker under the name Blue', async () => {
  const alex = as(A);
  await assertSucceeds(setDoc(doc(alex, 'rooms', 'r1', 'messages', 'b1'),
    { author: A, authorName: 'Blue', text: 'Try Ikseon-dong on day 2.', kind: 'blue', sentAt: serverTimestamp() }));
  // A "blue" message can't pretend to be from someone else's name.
  await assertFails(setDoc(doc(alex, 'rooms', 'r1', 'messages', 'b2'),
    { author: A, authorName: 'Mina', text: 'fake', kind: 'blue', sentAt: serverTimestamp() }));
  await assertFails(setDoc(doc(alex, 'rooms', 'r1', 'messages', 'b3'),
    { author: A, authorName: 'Alex', text: 'x', kind: 'admin', sentAt: serverTimestamp() }));
});

test('shared plan: the owner shares, an editor changes, viewers and strangers cannot', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await updateDoc(doc(db, 'rooms', 'r1'), {
      memberIds: arrayUnion(M), [`members.${M}`]: { name: 'Mina', handle: 'mina', role: 'editor' },
    });
    await setDoc(doc(db, 'rooms', 'r2'), {
      name: 'View only', owner: A, memberIds: [A, M], friendsCanEdit: false, createdAt: Timestamp.now(),
      members: { [A]: { name: 'Alex', handle: 'alex_k', role: 'owner' }, [M]: { name: 'Mina', handle: 'mina', role: 'viewer' } },
    });
  });
  const stop = (uid, name, extra = {}) => ({ date: Timestamp.fromDate(new Date('2026-12-03T10:00:00Z')), title: 'teamLab Planets',
    detail: 'art', kind: 'See', addedBy: uid, addedByName: name, updatedAt: serverTimestamp(), cost: 25, note: 'Book ahead', address: 'Toyosu', ...extra });
  const alex = as(A), mina = as(M), ken = as(K);
  // Owner shares the plan (batch).
  const b = writeBatch(alex);
  b.set(doc(alex, 'rooms', 'r1', 'plan', 's1'), stop(A, 'Alex'));
  b.set(doc(alex, 'rooms', 'r1', 'plan', 's2'), stop(A, 'Alex', { title: 'Shibuya Sky', kind: 'See' }));
  await assertSucceeds(b.commit());
  // Editor moves a stop; can't rewrite who added it.
  await assertSucceeds(setDoc(doc(mina, 'rooms', 'r1', 'plan', 's1'), stop(A, 'Alex', { editedByName: 'Mina' })));
  await assertFails(setDoc(doc(mina, 'rooms', 'r1', 'plan', 's2'), stop(M, 'Mina')));
  await assertSucceeds(getDoc(doc(mina, 'rooms', 'r1', 'plan', 's1')));
  // Strangers can't read or write; viewers can't write.
  await assertFails(getDoc(doc(ken, 'rooms', 'r1', 'plan', 's1')));
  await assertFails(setDoc(doc(ken, 'rooms', 'r1', 'plan', 's9'), stop(K, 'Ken')));
  await assertFails(setDoc(doc(mina, 'rooms', 'r2', 'plan', 's1'), stop(M, 'Mina')));
  await assertSucceeds(setDoc(doc(alex, 'rooms', 'r2', 'plan', 's1'), stop(A, 'Alex')));
  // Editor removes a stop.
  await assertSucceeds(deleteDoc(doc(mina, 'rooms', 'r1', 'plan', 's2')));
});
