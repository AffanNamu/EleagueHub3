// Mirrors ChatMessage.pinnedPreview()/replyPreview() in
// lib/features/chat/models/chat_message.dart — the short text shown for a
// message when it's pinned or being replied to.

export interface PreviewableMessage {
  deleted?: boolean;
  type?: string;
  text?: string;
}

export function chatMessagePreview(msg: PreviewableMessage): string {
  if (msg.deleted) return 'This message was deleted';

  const trimmed = (msg.text ?? '').trim();
  const hasText = trimmed.length > 0;

  switch (msg.type) {
    case 'image':
      return hasText ? trimmed : 'Photo';
    case 'voice':
      return hasText ? trimmed : 'Voice message';
    case 'code':
      return hasText ? trimmed : 'Code';
    default:
      return hasText ? trimmed : 'Message';
  }
}
