class LoanProduct
  include DataMapper::Resource  
  before :save, :convert_blank_to_nil

  property :id, Serial, :nullable => false, :index => true
  property :name, String, :nullable => false, :index => true, :min => 3
#  property :reference, String
  property :max_amount, Integer, :nullable => false, :index => true
  property :min_amount, Integer, :nullable => false, :index => true
  property :amount_multiple, Float, :nullable => false, :index => true, :default => 1, :min => 0.01
  property :max_interest_rate, Float, :nullable => false, :index => true, :max => 100
  property :min_interest_rate, Float, :nullable => false, :index => true, :min => 0
  property :interest_rate_multiple, Float, :nullable => false, :index => true, :default => 0.1
  property :installment_frequency, Enum.send('[]', *([:any] + INSTALLMENT_FREQUENCIES)), :nullable => true, :index => true

  property :max_number_of_installments, Integer, :nullable => false, :index => true, :max => 1000
  property :min_number_of_installments, Integer, :nullable => false, :index => true, :min => 0

  #This property is defined in init.rb after app load as Loan may not have loaded by the time this class initializes
  #  property :loan_type, Enum.send('[]'), :nullable => false, :index => true
  property :loan_type_string, String
 
  # this is a dirty hack. all this should go into the RepaymentStyle
  property :rounding, Integer
  property :rounding_style, Enum.send('[]', *['', 'round', 'floor', 'ceil']), :default => 'round', :nullable => true, :index => true

  property :valid_from, Date, :nullable => false, :index => true
  property :valid_upto, Date, :nullable => false, :index => true
  
  property :created_at, DateTime, :nullable => false, :default => DateTime.now
  property :updated_at, DateTime, :nullable => true

  property :payment_validation_methods, Text
  property :loan_validation_methods, Text
  property :linked_to_insurance, Boolean, :nullable => false, :index => true, :default => false
  property :insurance_product_id, Integer, :nullable => true, :index => true

  has n, :fees, :through => Resource#, :mutable => true
  has n, :loans
  has n, :audit_trails, :auditable_type => "LoanProduct", :child_key => ["auditable_id"]
  
  belongs_to :insurance_product, :nullable => true
  belongs_to :repayment_style

  belongs_to :organization, :parent_key => [:org_guid], :child_key => [:parent_org_guid], :required => false
  property   :parent_org_guid, String, :nullable => true
  
  belongs_to :domain, :parent_key => [:domain_guid], :child_key => [:parent_domain_guid], :required => false
  property   :parent_domain_guid, String, :nullable => true

  validates_with_method :min_is_less_than_max
  validates_is_unique   :name
  validates_is_number   :max_amount, :min_amount
  # validates_with_method :check_loan_type_correctness

  # while migrating, we have to provde a reference for every data point
  # this is for reasons of sanity.
  # validates_present :reference, :if => Proc.new{|t| Mfi.first.state == :migration}
  
  def self.from_csv(row, headers)
    min_interest = row[headers[:min_interest_rate]].to_f < 1 ? row[headers[:min_interest_rate]].to_f*100 : row[headers[:min_interest_rate]]
    max_interest = row[headers[:max_interest_rate]].to_f < 1 ? row[headers[:max_interest_rate]].to_f*100 : row[headers[:max_interest_rate]]
    obj = new(:name => row[headers[:name]], :min_amount => row[headers[:min_amount]], :max_amount => row[headers[:max_amount]], 
              :min_interest_rate => min_interest, :max_interest_rate => max_interest, 
              :min_number_of_installments => row[headers[:min_number_of_installments]], 
              :max_number_of_installments => row[headers[:max_number_of_installments]], 
              :installment_frequency => row[headers[:installment_frequency]].downcase.to_sym,
              :valid_from => Date.parse(row[headers[:valid_from]]), :valid_upto => Date.parse(row[headers[:valid_upto]]),
              :loan_type_string => row[headers[:loan_type]],
              :repayment_style => RepaymentStyle.first(:name => row[headers[:repayment_style]]), :upload_id => row[headers[:upload_id]])
    [obj.save, obj]
  end

  def payment_validations
    (payment_validation_methods or "").split(",").map{|m| m.to_sym}
  end

  def loan_validations
    (loan_validation_methods or "").split(",").map{|m| m.to_sym}
  end

  def self.valid(date=Date.today)
    LoanProduct.all(:valid_from.lte => date, :valid_upto.gte => date) 
  end

  def check_loan_type_correctness
    if loan_type_string and not loan_type_string.blank? and Loan.descendants.collect{|x| x.to_s}.include?(loan_type_string)
      self.loan_type_string = Loan.descendants.find{|x| x.to_s == loan_type_string}
      self.loan_type = self.loan_type_string unless (self.loan_type and not self.loan_type.blank?)
      return true
    elsif loan_type_string.blank? and loan_type and Loan.descendants.collect{|x| x.to_s}.include?(loan_type.to_s) 
      self.loan_type_string = loan_type.to_s
      self.loan_type = self.loan_type_string unless (self.loan_type and not self.loan_type.blank?)
      return true
    else
      return false
    end
  end

  def self.is_valid(id)
    return false unless product = LoanProduct.get(id)
    if product.valid_from<=Date.today and product.valid_upto>=Date.today
      return product
    else
      return false
    end    
  end
  
  def min_is_less_than_max
    if max_amount and min_amount and max_amount < min_amount
      [ false, "Minimum amount cannot be greater than maximum amount" ]
    elsif max_interest_rate and min_interest_rate and max_interest_rate.to_f < min_interest_rate.to_f
      [ false, "Minimum interest rate cannot be greater than maximum interest rate" ]
    elsif valid_from and valid_upto and valid_upto < valid_from
      [ false, "Valid from date cannot be greater than valid upto date" ]
    else
      return true
    end
  end
  
  def to_s
    "Loans of Rs. #{(max_amount==min_amount ? max_amount : min_amount.to_s+'-'+max_amount.to_s)} at #{(max_interest_rate==min_interest_rate ? max_interest_rate : min_interest_rate.to_s+'% - '+max_interest_rate.to_s+'%')}"
  end

  private
  def convert_blank_to_nil
    self.attributes.each{|k, v|
      if v.is_a?(String) and v.empty? and self.class.properties.find{|x| x.name == k}.type==Integer
        self.send("#{k}=", nil)
      end
    }
  end

end
