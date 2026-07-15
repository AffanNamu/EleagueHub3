export type ChatMessageType = 'text' | 'image' | 'code' | 'voice';

export interface ChatMessage {
  messageId: string;
  senderId: string;
  senderName: string;
  senderPhoto: string;
  text: string;
  imageUrl: string;
  voiceUrl: string;
  type: ChatMessageType;
  leagueId?: string;
  timestamp: number;
  createdAtMs: number;
  createdAt?: any; // Firestore ServerTimestamp
  pinned: boolean;
  pinnedAt?: any;
  pinnedBy: string;
  deleted: boolean;
  deletedAt?: any;
  deletedBy: string;
  replyToMessageId?: string;
  replyToSenderName?: string;
  replyToText?: string;
  replyToType?: string;
}
