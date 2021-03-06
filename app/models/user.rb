class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :omniauthable, :omniauth_providers => [ :facebook, :google_oauth2]

  has_many :borrowed, :foreign_key => 'borrower_id', :class_name => 'Transaction'
  has_many :lent_out, :foreign_key => 'lender_id', :class_name => 'Transaction'
  has_many :lenders, through: :borrowed
  has_many :borrowers, through: :lent_out
  has_many :debits, foreign_key: 'borrower_id'
  has_many :debits, foreign_key: 'lender_id'
  has_many :credits, foreign_key: 'lender_id'
  has_many :credits, foreign_key: 'borrower_id'

  has_many :friendships
  has_many :friends, :through => :friendships
  has_many :relationships


  scope :lent_amount, -> { order ('lent_out DESC LIMIT 5') }

  attr_accessor :flash_notice


  accepts_nested_attributes_for :friends

  def friends_attributes=(attributes)

  attributes["friend_ids"].each do |attribute|
    if attribute != ""
     friend = User.find_or_create_by(id: attribute)
        if !self.friends.include?(friend)
          self.friends << friend
        end
      end
   end
   self.save
  end

  def friends_attributes
    self.friends.uniq
  end




  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0,20]
      user.name = auth.info.name   # assuming the user model has a name
      # user.image = auth.info.image # assuming the user model has an image
    end
  end




  def add_money(money)
    self.balance + money
  end

    def total_borrowed_from(lender_id)
      borrowed.where(lender_id: lender_id).sum(:amount)
    end

    def total_lended(borrower_id)
      lent_out.where(borrower_id: borrower_id).sum(:amount)
    end

    def unique_lenders
      lenders.distinct
    end

    def unique_borrowers
      borrowers.distinct
    end

    def total_amount_due(current_user, lender)
       debit= Debit.find_or_create_by(borrower_id: current_user.id, lender_id: lender.id)
       credit = Credit.find_or_create_by(borrower_id: current_user.id, lender_id: lender.id)

       debit.amount - credit.amount
    end

    def borrower_total_amount_due(current_user, borrower)
       debit= Debit.find_or_create_by(borrower_id: borrower.id, lender_id: current_user.id)
       credit = Credit.find_or_create_by(borrower_id: borrower.id, lender_id: current_user.id)

       debit.amount - credit.amount
    end

    def lender_amount_not_zero(current_user)
      collection = []
      unique_lenders.each do |lender|

        if lender.total_amount_due(current_user, lender) != 0
          collection << lender
        end
      end
      collection
    end

    def borrower_amount_not_zero(current_user)
      collection = []
      unique_borrowers.each do |borrower|

        if borrower_total_amount_due(current_user, borrower) != 0
          collection << borrower
        end
      end
      collection
    end

    def overpaid_lender(current_user)
      collection = []
      lender_amount_not_zero(current_user).each do |lender|
      if total_amount_due(current_user, lender) < 0
        collection << lender
        end
      end
      collection
    end

    def display_overpaid_amount(current_user, user)
      current_user.overpaid_lender(current_user).include?(user)
    end

    def overpaid_borrower(current_user)
      collection = []
      borrower_amount_not_zero(current_user).each do |borrower|
      if borrower.borrower_total_amount_due(current_user, borrower) < 0
        collection << borrower
        end
      end
      collection
    end

def return_json

    return_val = []
    self.friends.each do |friend|
      obj = {}
      obj[:friend] = friend
      obj[:amount] = self.total_amount_due(self, friend)
      obj[:borrower] = self.borrower_total_amount_due(self, friend)
      return_val << obj
    end
    return_val
end

def friend_relationship(current_user, friend_id)

  rel = Friendship.find_by(user_id: current_user, friend_id: friend_id)
  rel.relationship
end

def update_friends(user_name, e)
  if user_name !=""
    person = User.new(name:user_name.strip, email: e)
    person.save(validate:false)
    new_friend =Friendship.create(user_id:self.id, friend_id:person.id)
  end
end


def create_this_transaction(current_user, friend, amount_params)
  if amount_params != "" && amount_params != "0"
    @transaction = Transaction.new(lender_id: current_user.id, borrower_id: friend, amount: amount_params)

    if @transaction.save
    else
      self.flash_notice = @transaction.errors.full_messages[0]

    end
  end
end

def setting_default_relationship(drop_params)
  if drop_params[:relationship_id].to_i != 0
    word = drop_params[:relationship_id].to_i
  else
    word = 1
  end
  word
end

def setting_relationship_variable(current_user, new_user_info, new_word)
  new_friend_relationship = Friendship.find_by(user_id: current_user.id, friend_id: new_user_info)
  new_friend_relationship.update(relationship: new_word.description)
end


def creating_relationship_transaction_friend(user_name, rel_params, drop_params, amount_params, current_user )
  if user_name != ""
    if rel_params[:description] == ""
    word = self.setting_default_relationship(drop_params)
    new_user_info = User.last.id
    new_word = Relationship.find(word)
    self.setting_relationship_variable(current_user, new_user_info, new_word)
    self.create_this_transaction(current_user, new_user_info, amount_params)
    end
  else
    if rel_params[:description] != ""
      self.setting_default_relationship(drop_params)
      new_word =Relationship.find_or_create_by(description: rel_params[:description])
      new_user_info = User.last.id

      self.setting_relationship_variable(current_user, new_user_info, new_word)
      friend_id = User.last.id
      self.create_this_transaction(current_user, friend_id, amount_params)
    end
  end
end

def update_relationship_variable(word, friend)
  new_word = Relationship.find(word)
  friend.update(relationship: new_word.description)
end


def create_attributes_with_existing_friends(drop_params, rel_params, friend_params, user_params, current_user, amount_params)
    word = self.setting_default_relationship(drop_params)
    if rel_params[:description] == ""

      if friend_params[:friend_id] != friend_params[:user_id]
        friend = Friendship.find_or_create_by(friend_params)

        self.update_relationship_variable(word, friend)

      end
      user_params[:friends_attributes][:friend_ids].each do |friend_att|
        if friend_att != ""
          friend = User.find(friend_att)
          set_friend = Friendship.find_or_create_by(friend_id: friend.id, user_id: current_user.id)
          self.update_relationship_variable(word, set_friend)
          friend = friend.id
          self.create_this_transaction(current_user, friend, amount_params)
        end
      end
    else
      new_word =Relationship.find_or_create_by(description: rel_params[:description])

      user_params[:friends_attributes][:friend_ids].each do |friend_att|

        if friend_att != ""
          friend = User.find(friend_att)
          if friend.id != current_user.id

            set_relationship = Friendship.find_or_create_by(friend_id: friend.id, user_id: current_user.id)
            set_relationship.update(relationship: new_word.description)
            friend = friend.id

            self.create_this_transaction(current_user, friend, amount_params)
        end
      end
    end
  end
end




  #   if self.lender_ids.include?(lender.to_i)
  #     lender = User.find(lender.to_i)
  #   end
  # end

end
