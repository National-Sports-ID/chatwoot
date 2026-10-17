module ReportingEventHelper
  def business_hours(inbox, from, to)
    return 0 unless inbox.working_hours_enabled?

    inbox_working_hours = configure_working_hours(inbox.working_hours)
    return 0 if inbox_working_hours.blank?

    # Configure working hours
    WorkingHours::Config.working_hours = inbox_working_hours

    # Configure timezone
    WorkingHours::Config.time_zone = inbox.timezone

    # Use inbox timezone to change from & to values.
    from_in_inbox_timezone = from.in_time_zone(inbox.timezone).to_time
    to_in_inbox_timezone = to.in_time_zone(inbox.timezone).to_time
    from_in_inbox_timezone.working_time_until(to_in_inbox_timezone)
  end

  def last_non_human_activity(conversation)
    # Try to get either a handoff or reopened event first
    # These will always take precedence over any other activity
    # Also, any of these events can happen at any time in the course of a conversation lifecycle.
    # So we pick the latest event
    event = ReportingEvent.where(
      conversation_id: conversation.id,
      name: %w[conversation_bot_handoff conversation_opened]
    ).order(event_end_time: :desc).first

    return event.event_end_time if event&.event_end_time

    # Fallback to bot resolved event
    # Because this will be closest to the most accurate activity instead of conversation.created_at
    bot_event = ReportingEvent.where(conversation_id: conversation.id, name: 'conversation_bot_resolved').last

    return bot_event.event_end_time if bot_event&.event_end_time

    # If no events found, return conversation creation time
    conversation.created_at
  end

  private

  def configure_working_hours(working_hours)
    split_working_hours(working_hours).transform_values { |ranges| merge_ranges(ranges) }
  end

  # The working_hours gem rejects a range that ends before it starts, so an overnight
  # slot is split: open until 24:00 on its day, then 00:00 to closing on the next.
  def split_working_hours(working_hours)
    working_hours.reject(&:closed_all_day?).flat_map { |wh| slot_ranges(wh) }
                 .each_with_object({}) { |(day, start, finish), object| (object[day] ||= {})[start] = finish }
  end

  def slot_ranges(working_hour)
    open_at = format_time(working_hour.open_hour, working_hour.open_minutes)
    close_at = format_time(working_hour.close_hour, working_hour.close_minutes)
    today = day(working_hour.day_of_week)
    return [[today, open_at, close_at]] unless working_hour.overnight?

    ranges = [[today, open_at, '24:00']]
    ranges << [day((working_hour.day_of_week + 1) % 7), '00:00', close_at] unless close_at == '00:00'
    ranges
  end

  # A night shift's tail can meet the next day's own range (e.g. an all-day slot);
  # the gem refuses overlapping ranges, so join them.
  def merge_ranges(ranges)
    ranges.sort.each_with_object([]) do |(start, finish), merged|
      if merged.any? && start <= merged.last[1]
        merged.last[1] = [merged.last[1], finish].max
      else
        merged << [start, finish]
      end
    end.to_h
  end

  def day(day_of_week)
    week_days = {
      0 => :sun,
      1 => :mon,
      2 => :tue,
      3 => :wed,
      4 => :thu,
      5 => :fri,
      6 => :sat
    }
    week_days[day_of_week]
  end

  def format_time(hour, minute)
    hour = hour < 10 ? "0#{hour}" : hour
    minute = minute < 10 ? "0#{minute}" : minute
    "#{hour}:#{minute}"
  end
end
