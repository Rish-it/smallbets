module Message::Broadcasts
  def broadcast_create
    broadcast_append_to room, :messages, target: [ room, :messages ], partial: "messages/message", locals: { current_room: room }
    ActionCable.server.broadcast("unread_rooms", { roomId: room.id, roomSize: room.messages_count, roomUpdatedAt: created_at.iso8601 })

    broadcast_notifications
    broadcast_to_inbox_mentions if has_mentions?
    broadcast_to_inbox_threads if in_thread?
  end

  def broadcast_update
    broadcast_notifications(ignore_if_older_message: true)
  end

  def broadcast_notifications(ignore_if_older_message: false)
    memberships = room.memberships.where(user_id: mentionee_ids)

    memberships.each do |membership|
      next if ignore_if_older_message && (membership.read? || membership.unread_at > created_at)

      ActionCable.server.broadcast "user_#{membership.user_id}_notifications", { roomId: room.id }
    end
  end

  def broadcast_reactivation
    previous_message = room.messages.active.order(:created_at).where("created_at < ?", created_at).last
    if previous_message.present?
      target = previous_message
      action = "after"
    else
      target = [ room, :messages ]
      action = "prepend"
    end

    broadcast_action_to room, :messages,
                        action:,
                        target:,
                        partial: "messages/message",
                        locals: { message: self, current_room: room },
                        attributes: { maintain_scroll: true }
  end

  private

  def has_mentions?
    mentionee_ids.any?
  end

  def in_thread?
    room.thread?
  end

  def broadcast_to_inbox_mentions
    # Broadcast to each mentioned user's mentions view
    mentionees.each do |user|
      next if user.id == creator_id # Don't broadcast to the creator

      broadcast_prepend_to "user_#{user.id}_inbox_mentions",
                           target: "inbox",
                           partial: "messages/message",
                           locals: { message: self, timestamp_style: :long_datetime, show_date_separator: false }
    end
  end

  def broadcast_to_inbox_threads
    # When a reply is posted in a thread, update the threads view
    # This should refresh the parent message's position in the threads list
    return unless room.thread? && room.parent_message

    parent_message = room.parent_message

    # Find users who should see this thread
    # Users with visible membership in the thread OR everything involvement in parent room
    thread_memberships = room.memberships.active.visible
    parent_room_memberships = parent_message.room.memberships.active.involved_in_everything

    all_user_ids = (thread_memberships.pluck(:user_id) + parent_room_memberships.pluck(:user_id)).uniq

    all_user_ids.each do |user_id|
      # Replace the parent message in the threads list to update its position/content
      broadcast_replace_to "user_#{user_id}_inbox_threads",
                           target: ActionView::RecordIdentifier.dom_id(parent_message),
                           partial: "messages/message",
                           locals: { message: parent_message, timestamp_style: :long_datetime, show_date_separator: false }
    end
  end
end
