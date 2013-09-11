class Entry < ActiveRecord::Base
  include ActionView::Helpers
  belongs_to :feed, counter_cache: true
  has_many :user_states, dependent: :destroy
  has_many :subscriptions, through: :feed

  validates :feed_id, presence: true

  default_scope { order('entries.published DESC, entries.id DESC') }

  scope :seen_by, -> (user) { joins(:user_states).where(user_states: {user_id: user, seen: true}) }
  scope :unseen_by, -> (user) {
    # slow for huge, otherwise unconstrained collections of entries
    where.not(id: UserState.select(:entry_id).where(user: user, seen: true))
  }

  scope :starred, -> { joins(:user_states).where(user_states: {starred: true}) }
  scope :starred_by, -> (user) { joins(:user_states).where(user_states: {user_id: user, starred: true}) }

  scope :subscribed_by, -> (user) { joins(:subscriptions).where(subscriptions: {user: user}) }

  def unseen?(user)
    state = self.user_states.where(user: user).first
    state.nil? || state.seen?
  end

  def subscribed_by?(user)
    feed.subscriptions.where(user: user).exists?
  end

  def userstate(user)
    user_states.find_by(user: user) or UserState.new(user: user, entry: self)
  end

  def snippet
    truncate(strip_tags((self.summary or self.content or '')), length: 200, separator: ' ')
  end

  def text
    (self.content || self.summary || '')
  end

  def timestr
    if self.published
      time_ago_in_words(self.published).sub('about', '~').sub(/ hours?/, 'h')
    else
      ''
    end
  end

  def self.remove_duplicates
    dupecount = 0
    groups = Entry
      .select('title, url, author, summary, content, published, COUNT(*) AS count')
      .group(:title, :url, :author, :summary, :content, :published)
      .having('count > 1')
    self.transaction do
      groups.each do |grp|
        duplicates = Entry
          .where(
            title: grp.title, url: grp.url, author: grp.author,
            summary: grp.summary, content: grp.content, published: grp.published)
          .to_a
        original = duplicates.shift
        logger.info "removing #{duplicates.size} duplicates of entry [#{original.id}: #{original.title}] (#{original.feed.title})"
        duplicates.each do |e|
          e.destroy
          dupecount += 1
        end
      end

    end
    logger.info "#{dupecount} duplicated removed."
  end

end
