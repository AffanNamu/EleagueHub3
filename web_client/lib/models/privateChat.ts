// lib/models/privateChat.ts
//
// Mirrors lib/features/chat/models/private_message.dart and
// private_thread.dart field-for-field.

export type PrivateMessageType = 'text' | 'image' | 'voice';

export interface PrivateMessage {
  id: string;
  senderId: string;
  type: PrivateMessageType;
  text: string;
  imageUrl: string;
  voiceUrl: string;
  createdAtMs: number;
}

export interface PrivateThread {
  id: string;
  participantIds: string[];
  initiatedBy: string;
  lastMessage: string;
  lastMessageAtMs: number;
  lastSenderId: string;
  createdAtMs: number;
}

export function otherParticipant(thread: PrivateThread, selfUid: string): string {
  return thread.participantIds.find((id) => id !== selfUid) ?? '';
}

function asInt(v: unknown): number {
  if (typeof v === 'number') return Math.trunc(v);
  return 0;
}

function asString(v: unknown): string {
  return typeof v === 'string' ? v.trim() : '';
}

export function privateMessageTypeFromString(raw: unknown): PrivateMessageType {
  if (raw === 'image') return 'image';
  if (raw === 'voice') return 'voice';
  return 'text';
}

export function privateMessageFromDoc(id: string, data: Record<string, unknown>): PrivateMessage {
  return {
    id,
    senderId: asString(data.senderId),
    type: privateMessageTypeFromString(data.type),
    text: asString(data.text),
    imageUrl: asString(data.imageUrl),
    voiceUrl: asString(data.voiceUrl),
    createdAtMs: asInt(data.createdAtMs),
  };
}

export function privateThreadFromDoc(id: string, data: Record<string, unknown>): PrivateThread {
  const rawIds = Array.isArray(data.participantIds) ? data.participantIds : [];
  return {
    id,
    participantIds: rawIds.map((v) => String(v)),
    initiatedBy: asString(data.initiatedBy),
    lastMessage: asString(data.lastMessage),
    lastMessageAtMs: asInt(data.lastMessageAtMs),
    lastSenderId: asString(data.lastSenderId),
    createdAtMs: asInt(data.createdAtMs),
  };
}
