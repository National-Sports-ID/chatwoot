# == Schema Information
#
# Table name: working_hours
#
#  id             :bigint           not null, primary key
#  close_hour     :integer
#  close_minutes  :integer
#  closed_all_day :boolean          default(FALSE)
#  day_of_week    :integer          not null
#  open_all_day   :boolean          default(FALSE)
#  open_hour      :integer
#  open_minutes   :integer
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint
#  inbox_id       :bigint
#
# Indexes
#
#  index_working_hours_on_account_id  (account_id)
#  index_working_hours_on_inbox_id    (inbox_id)
#
class WorkingHour < ApplicationRecord
  belongs_to :inbox

  before_validation :ensure_open_all_day_hours
  before_save :assign_account

  validates :open_hour,     presence: true, unless: :closed_all_day?
  validates :open_minutes,  presence: true, unless: :closed_all_day?
  validates :close_hour,    presence: true, unless: :closed_all_day?
  validates :close_minutes, presence: true, unless: :closed_all_day?

  validates :open_hour,     inclusion: 0..23, unless: :closed_all_day?
  validates :close_hour,    inclusion: 0..23, unless: :closed_all_day?
  validates :open_minutes,  inclusion: 0..59, unless: :closed_all_day?
  validates :close_minutes, inclusion: 0..59, unless: :closed_all_day?

  validate :close_differs_from_open, unless: :closed_all_day?
  validate :open_all_day_and_closed_all_day

  def self.today
    # While getting the day of the week, consider the timezone as well. `first` would
    # return the first working hour from the list of working hours available per week.
    inbox = first.inbox
    find_by(day_of_week: Time.zone.now.in_time_zone(inbox.timezone).to_date.wday)
  end

  # NSID: a closing time at or before the opening time means the shift ends after
  # midnight (7:00 AM - 2:00 AM). This covers the part on the slot's own day.
  def open_at?(time)
    return false if closed_all_day?
    return true if open_all_day?

    minute = minute_of_day(time.in_time_zone(inbox.timezone))
    return minute >= open_time_in_minutes if overnight?

    minute.between?(open_time_in_minutes, close_time_in_minutes)
  end

  # The part of an overnight shift that runs into the next day.
  def open_past_midnight_at?(time)
    overnight? && minute_of_day(time.in_time_zone(inbox.timezone)) < close_time_in_minutes
  end

  def overnight?
    !closed_all_day? && !open_all_day? && close_time_in_minutes <= open_time_in_minutes
  end

  def open_now?
    inbox_time = Time.zone.now.in_time_zone(inbox.timezone)
    open_at?(inbox_time)
  end

  def closed_now?
    !open_now?
  end

  private

  def assign_account
    self.account_id = inbox.account_id
  end

  def close_differs_from_open
    return if open_hour.nil? || open_minutes.nil? || close_hour.nil? || close_minutes.nil?
    return unless open_time_in_minutes == close_time_in_minutes

    errors.add(:close_hour, 'Closing time cannot be the same as opening time')
  end

  def open_time_in_minutes
    (open_hour.to_i * 60) + open_minutes.to_i
  end

  def close_time_in_minutes
    (close_hour.to_i * 60) + close_minutes.to_i
  end

  def minute_of_day(time)
    (time.hour * 60) + time.min
  end

  def ensure_open_all_day_hours
    return unless open_all_day?

    self.open_hour = 0
    self.open_minutes = 0
    self.close_hour = 23
    self.close_minutes = 59
  end

  def open_all_day_and_closed_all_day
    return unless open_all_day? && closed_all_day?

    errors.add(:base, 'open_all_day and closed_all_day cannot be true at the same time')
  end
end
