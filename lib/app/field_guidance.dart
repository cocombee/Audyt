/// Brief field guidance. These explain inputs, not tax eligibility or legal advice.
String? accountingFieldGuidance(String label) {
  final name = label.replaceAll(' *', '').trim();
  return _fieldGuidance[name];
}

const _fieldGuidance = <String, String>{
  'Make Recurring': 'Choose a scheduled, reminder or unscheduled template, or No for a single transaction.',
  'Template Name': 'Name this reusable transaction template.',
  'Days In Advance': 'Days before the transaction date to prepare the scheduled entry or reminder.',
  'Days Before': 'Days before the transaction date to show its reminder.',
  'Day Of Week': 'Choose the weekday on which the template occurs.',
  'Schedule Name': 'Name this reusable transaction schedule.',
  'Repeat':
      'Choose whether this schedule repeats daily, weekly, monthly or yearly.',
  'Ends': 'Choose no end, a last date or a number of occurrences.',
  'Occurrence Count': 'Number of occurrences before the schedule ends.',
  'Preserve Month End': 'Keep occurrences on the month’s last day when the start date is month end.',
  'Interval': 'Choose how often the template repeats.',
  'Week Of Month': 'Choose a numbered day or a weekday position in the month.',
  'Day Of Month': 'Day on which the template occurs.',
  'Month Of Year': 'Month in which the yearly template occurs.',
  'End': 'Choose no end, an end date or an occurrence count.',
  'End Date': 'Last date on which this template may occur.',
  'Occurrences': 'Number of occurrences before the template ends.',
  'Received From': 'Choose the party providing these funds.',
  'Cash Back Account': 'Account to which the cash back portion is assigned.',
  'Cash Back Memo': 'Description of the cash back portion.',
  'Cash Back Amount': 'Cash retained from the funds rather than deposited.',
  'This Is A Credit Card': 'Identify this payment method as a credit card.',
  'Due Rule': 'Choose a fixed number of days after issue or a monthly due day.',
  'Due In Days': 'Enter the whole number of days after issue; zero is due on receipt.',
  'This Is A Credit Or Debit Card':
      'Identify this payment method as a credit or debit card.',
  'Credit Card Account': 'Choose the company credit card account affected by this payment or credit.',
  'Payee': 'Choose the person or business this payment or credit relates to.',
  'Funding Bank Account':
      'Choose the company bank account paying this card balance.',
  'Paid By Cheque': 'Select when this card payment was made by cheque, then enter its cheque number.',
  'Permit Number':
      'Enter the permit number from the supporting document, if applicable.',
  'Number Format': 'Comma groups thousands; a dot separates decimal places. This is the current reporting format.',
  'Period From': 'First date of the accounting period under review.',
  'Period Through': 'Last date of the accounting period under review.',
  'Bank Reconciliation':
      'Review each statement and unresolved bank difference for this period.',
  'Receivables And Payables':
      'Review outstanding balances, allocations and overdue items.',
  'Missing Documents':
      'Check transactions lacking sufficient supporting evidence.',
  'Draft And Unposted Entries':
      'Review pending entries before closing; do not omit them silently.',
  'Tax Reconciliation':
      'Compare applicable tax balances with returns and payments.',
  'Accruals And Prepayments':
      'Review costs and income assigned to the correct period.',
  'Asset Depreciation':
      'Review the asset register and proposed depreciation for this period.',
  'Review Conclusion':
      'Record a review outcome; this preview does not lock the ledger.',
  'Asset Name': 'Identify the capital asset in the register.',
  'Asset Reference': 'Internal asset tag or identifier.',
  'Acquisition Date':
      'Date the asset was acquired, supported by the purchase document.',
  'In Service Date': 'Date the asset became available for use.',
  'Cost': 'Acquisition cost under the applicable accounting policy.',
  'Residual Value': 'Estimated value remaining at the end of useful life.',
  'Useful Life In Months':
      'Accountant-reviewed expected useful life, expressed in months.',
  'Depreciation Method': 'Accounting policy for allocating cost; this is not a tax allowance calculation.',
  'Asset Account': 'Capital asset account linked to the original purchase.',
  'Accumulated Depreciation Account':
      'Contra-asset account for accumulated depreciation.',
  'Depreciation Expense Account': 'Expense account for depreciation charges.',
  'Invoice or Bill Number': 'Choose the invoice or bill this payment covers.',
  'Amount Applied to Document': 'Enter the payment amount for this document, up to its remaining balance.',
  'Credit To Apply':
      'Use an existing credit without creating duplicate income or expense.',
  'Payment Not Applied':
      'The portion of this payment that is not matched to a document.',

  'Transfer Date':
      'Date the external transfer took place; match against bank evidence.',
  'Bank Reference':
      'Reference supplied by the bank, not an internal document number.',
  'Linked Transaction':
      'Select the existing entry to avoid recording the movement twice.',
  'Deposit Account': 'Bank account receiving the deposit; currency follows its account master.',
  'Deposit Date':
      'Date the deposit was made, separate from cheque issuance or clearance.',
  'Deposit Source': 'Identify the existing receipts or funds being deposited.',
  'Linked Receipt Or Payment': 'Link the existing receipt or payment rather than recognizing income again.',
  'Direction': 'Issued means you gave the cheque; received means a payer gave it to you.',
  'Bank Account': 'Choose the company bank account affected by this record.',
  'Cheque Number': 'Number printed on the physical cheque.',
  'Cheque Date':
      'Date written on the cheque; preserve it separately from clearance.',
  'Payee Or Payer':
      'Who receives an issued cheque or provides a received cheque.',
  'Linked Payment Or Receipt':
      'Existing accounting record settled by this cheque.',
  'Cheque Status': 'Record the external cheque lifecycle. A scan does not establish clearance.',
  'Cleared Date':
      'Date bank evidence confirms clearance; leave empty until confirmed.',

  'Party Type': 'Choose the legal type of this customer or supplier.',
  'Preferred Billing Currency': 'Default for new documents only. This does not change a bank account currency or existing amounts.',
  'Tax Details Needed': 'Expand identity and tax details when needed for this party’s documents. Required e-Invoice checks happen before submission.',
  'Tax Identity Source': 'Use the company identity maintained in Business Profile, rather than entering a second copy.',
  'Address Line 1': 'Street number, building and street name.',
  'Address Line 2': 'Optional unit, floor or additional address information.',
  'City': 'Enter the city or town as used in the postal address.',
  'Postcode': 'Enter the postal code as text, including any leading zero.',
  'State / Region':
      'Select a Malaysian state or enter the region for an overseas address.',
  'Country Name': 'Enter the country name for this overseas address.',
  'Country ISO Code': 'Enter the two-letter country code, such as MY or SG. It is saved with this contact’s address.',
  'Vendor Type': 'Choose Supplier, Vendor or Small Provider. This classifies the contact; it does not create a purchase or payment.',
  'Identification Type': 'Choose the identifier appropriate to the party; do not treat a person as a registered business.',
  'Identification Number': 'Enter the identifier for the selected type. Keep the original formatting.',

  'Debit': 'Enter the amount to debit on this journal line. Total debits and credits must match.',
  'Credit': 'Enter the amount to credit on this journal line. Total debits and credits must match.',
  'Preview State': 'Choose a sign-in state to review its screen without connecting an account.',
  'Preview Role': 'Choose a sample role to inspect its intended access; this does not change your permissions.',
  'Monthly Due Day': 'Enter the day of the month on which payment becomes due.',
  'Rollover Within Days': 'Enter the minimum gap before the monthly due date; shorter gaps move payment to the following month.',

  "Business Name": "The business name customers see on your documents.",
  "Legal Name": "The exact name on your business registration.",
  "Business Type": "Choose the legal structure of your business.",
  "Registration Number": "Enter the registration number issued for this business or tax registration.",
  "Business Registration Number": "Enter the business registration number shown on your registration certificate.",
  "TIN": "Enter your tax identification number issued by the tax authority.",
  "Taxpayer TIN": "Enter the taxpayer identification number for this business.",
  "MSIC Code": "Enter the industry classification code for your registered business activity.",
  "SST Registration Number": "Enter the SST registration number issued to your business, if registered.",
  "Business Address":
      "Enter the registered business address, including postcode and country.",
  "Billing Address": "Enter the address to print on invoices for this contact.",
  "Country": "Choose the country of the business address.",
  "Email": "Enter the email address for accounting correspondence.",
  "Telephone": "Enter a contact number, including its country code.",
  "Website": "Enter your business website address.",
  "Business Logo": "Choose an image to represent your business on documents.",
  "Financial Year Starts": "Choose the first month of your financial year.",
  "Reporting Basis": "Choose whether reports recognise transactions when earned or incurred, or when cash moves.",
  "Basis": "Choose the accounting basis used for this report.",
  "Reporting Framework": "Choose the financial reporting framework applicable to your business, with your accountant.",
  "Home Currency": "Choose the currency used for your main accounting records.",
  "Currency": "Choose the currency in which this document is issued.",
  "Date Format": "Choose how dates appear throughout the app.",
  "Class": "Choose the department, activity or business segment for this transaction.",
  "Location": "Choose the branch or operating site for this transaction.",
  "Close Through Date":
      "Enter the last date of the accounting period to protect from changes.",
  "Closing Policy": "Choose whether changes to closed periods need approval or are prevented.",
  "Duplicate Warnings":
      "Flag repeated document references before saving a transaction.",
  "Receivables Account":
      "Choose the account that tracks money customers owe you.",
  "Payables Account": "Choose the account that tracks money you owe suppliers.",
  "Income Account": "Choose the account used to classify sales income.",
  "Expense Account": "Choose the account used to classify this cost.",
  "Sales Tax Liability Account":
      "Choose the liability account that tracks sales tax payable.",
  "Service Tax Liability Account":
      "Choose the liability account that tracks service tax payable.",
  "Discount Account": "Choose the account used to record discounts.",
  "Rounding Account": "Choose the account for genuine rounding differences, not unexplained imbalances.",
  "Retained Earnings Account":
      "Choose the equity account for accumulated earnings from prior periods.",
  "Jurisdiction":
      "Choose the country whose tax rules apply to this registration.",
  "Registration Status": "Choose the current status of this tax registration.",
  "Tax Family": "Choose the type of tax this registration or code belongs to.",
  "Tax Agency": "Choose the authority responsible for this tax.",
  "Agency": "Choose the authority responsible for this obligation.",
  "Effective From":
      "Enter the first date this registration or rule applies, in DD-MM-YYYY.",
  "Effective Through":
      "Enter the last date this rule applies, if it has an end date.",
  "Filing Frequency": "Choose the filing interval assigned to this obligation; it does not determine the legal deadline.",
  "Taxable Period Starts": "Enter the start date of the taxable period assigned to your registration.",
  "Tax Basis": "Choose the recognition basis required for this tax policy.",
  "Default Tax Mode": "Choose the default treatment of tax in entered prices; review exceptions per transaction.",
  "Tax Mode": "Choose whether prices include tax, exclude tax, or have another applicable treatment.",
  "Require Tax Review": "Require review of the selected tax treatment before finalising a transaction.",
  "Environment": "Choose Sandbox for testing or Production for live submissions when connected.",
  "Business Activity Description": "Briefly describe what your business does.",
  "Submission Mode": "Choose the appropriate individual, consolidated or self-billed document workflow.",
  "Customer Identification":
      "Choose the type of identifier supplied by the customer.",
  "Product Classification":
      "Enter the applicable classification code for the product or service.",
  "E-Invoice Classification":
      "Enter the applicable e-invoice classification code for this item.",
  "Review Before Submit":
      "Require approval before a document can be submitted.",
  "Default Payment Terms":
      "Choose the usual time customers have to pay invoices.",
  "Default Bill Terms": "Choose the usual time allowed to pay supplier bills.",
  "Payment Terms":
      "Choose when payment becomes due relative to the document date.",
  "Custom Term Value":
      "Enter the number of days or day of month required by your custom terms.",
  "Show Product / Service":
      "Show the product or service selection on transaction lines.",
  "Show Rate": "Show Rate and Quantity. Amount and Rate update each other automatically.",
  "Show Quantity": "Show an informational quantity field. Amount stays manual until Rate is enabled.",
  "Show SKU": "Show the stock-keeping code alongside an item.",
  "Enable Discounts": "Allow discounts on new transactions. Entered discounts stay editable when this is off.",
  "Show Class": "Show an optional Class tag on new transactions. Saved or entered tags stay editable when this is off.",
  "Customer Message": "Enter the message customers should see on invoices.",
  "Statement Message": "Enter the message customers should see on statements.",
  "Apply Customer Credits": "Choose whether customer credits are proposed for approval or selected manually.",
  "Track Items": "Record products or services separately on purchase lines.",
  "Link To Customer": "Link a cost to the customer it relates to.",
  "Billable Expenses":
      "Allow eligible customer-related costs to be marked for later billing.",
  "Purchase Orders": "Enable purchase-order preparation and reference fields.",
  "Require Bill Reference": "Require the supplier document number on a bill.",
  "Duplicate Bill Check":
      "Choose the information used to flag a possible duplicate bill.",
  "Match Bill Payments":
      "Choose how a payment is matched to outstanding documents.",
  "Document Type":
      "Choose the kind of accounting document these settings apply to.",
  "Number Prefix":
      "Enter the fixed text placed before a document sequence number.",
  "Next Number": "Enter the next unused number in this document sequence.",
  "Number Padding":
      "Choose how many digits to display, adding leading zeroes if needed.",
  "Reset Sequence": "Choose when the document number sequence starts again.",
  "Paper Size": "Choose the paper size used for printed documents.",
  "Show Logo": "Include your business logo on the document.",
  "Show Registration":
      "Include the business registration details on the document.",
  "Show Tax Breakdown": "Show tax amounts separately on the document.",
  "Footer": "Enter the short text printed at the bottom of each document.",
  "Obligation": "Choose the filing, payment or reporting duty to track.",
  "Reminder Type": "Choose the event the reminder is intended to track.",
  "Days Before Due Date":
      "Enter how many days before the due date the reminder should appear.",
  "Visible Reminders":
      "Show the nearest two, three or four saved deadlines on Home.",
  "Days Before Reminder":
      "Enter the number of days to use for this reminder offset.",
  "Repeat Interval In Days":
      "Enter the number of days between repeated reminders.",
  "Notify When Overdue":
      "Continue highlighting an obligation after its due date until resolved.",
  "Delivery":
      "Choose where reminders should appear when notifications are connected.",
  "Transaction Approval":
      "Choose which transactions should require review before posting.",
  "Approval Threshold": "Enter the amount above which approval is required, in the applicable currency.",
  "Approver": "Enter the person responsible for reviewing these transactions.",
  "Review Suggestions":
      "Require review before accepting an automatically suggested transaction.",
  "Scan Documents": "Extract proposed details from uploaded receipts or documents for review.",
  "Confirm Extracted Date":
      "Require confirmation of a scanned date before it is used.",
  "Confirm Category":
      "Require a category choice before finalising an uploaded document.",
  "Duplicate Detection": "Choose how likely duplicate uploads are identified.",
  "Filename Conflict":
      "Choose what should happen if a destination filename already exists.",
  "Multiple Attachments": "Choose how multiple source files should be organised for one transaction.",
  "Print Output": "Choose which document version should be used for printing.",
  "Preserve Original Files": "Keep uploaded originals unchanged; edits belong to separate working copies.",
  "Name": "Enter the name used to identify this record.",
  "Display Name": "Enter the name shown in lists and selectors.",
  "Role": "Choose the level of accounting access for this person.",
  "Can Approve Transactions":
      "Allow this role to approve transactions for posting.",
  "Can Change Settings":
      "Allow this role to change business and accounting settings.",
  "Can Export Reports": "Allow this role to export accounting reports.",
  "Status": "Choose the current state of this record.",
  "Active": "Keep this record available for new transactions.",
  "Backup Frequency": "Choose how often Audyt backs up while open, with catch-up at the next launch.",
  "Backup Destination":
      "Specify the folder where accounting backups should be stored.",
  "Include Original Documents":
      "Include unchanged supporting files in the backup or export.",
  "Export Format": "Choose the file format for the exported records.",
  "Export": "Choose the file format for this report export.",
  "Date Range": "Choose the period of records to include.",
  "From Date": "Enter the first date to include, in DD-MM-YYYY.",
  "Through Date": "Enter the last date to include, in DD-MM-YYYY.",
  "Customer": "Enter the customer this sale or receipt belongs to.",
  "Vendor": "Enter the supplier this purchase or payment belongs to.",
  "Counterparty": "Enter the customer or supplier named on this document.",
  "Date": "Enter the date shown on the transaction document, in DD-MM-YYYY.",
  "Transaction Date": "Enter the accounting transaction date, in DD-MM-YYYY.",
  "Payment Date":
      "Enter the date the payment was made or received, in DD-MM-YYYY.",
  "Due Date":
      "Enter the last date payment or submission is due, in DD-MM-YYYY.",
  "Document Number": "Enter the unique number identifying this document.",
  "Reference": "Enter the external reference that helps match this transaction to its source.",
  "Document Reference":
      "Enter the reference printed on the supporting document.",
  "Memo": "Add an internal note that explains the transaction.",
  "Notes":
      "Add relevant details that will help someone review this record later.",
  "Payment Method": "Choose how the money was paid or received.",
  "Payment Account":
      "Choose the bank, cash or clearing account used for this payment.",
  "Amount": "Enter the document or payment amount in the selected currency.",
  "How to Match Payment":
      "Choose how this amount should be applied to outstanding documents.",
  "Source Document":
      "Enter the invoice, bill or other document this record relates to.",
  "Category": "Choose the accounting category that describes the transaction.",
  "Category Code":
      "Enter the short category code used in filenames, such as GAS.",
  "SKU": "Enter your internal stock-keeping code for this item.",
  "Type": "Choose the kind of record or item you are creating.",
  "Description":
      "Describe the goods, services or purpose represented by this line.",
  "Sales Rate": "Enter the selling price per unit.",
  "Purchase Cost": "Enter the purchase cost per unit.",
  "Tax Code":
      "Choose or enter the applicable tax code for this transaction line.",
  "Purchase Treatment":
      "Choose how purchases of this item should be classified.",
  "Rate Type": "Choose whether this rule uses a percentage or a fixed amount.",
  "Rate / Amount": "Enter the applicable percentage or fixed amount; confirm the rule and effective date first.",
  "Liability Account": "Choose the account used to track the amount owed.",
  "Return Line": "Enter the return line or box this tax code should map to.",
  "Legal Source":
      "Enter the official source or reference supporting this rule.",
  "Period": "Choose the reporting period to inspect.",
  "Return Status": "Choose the current preparation, submission or payment status of the return.",
  "Submission Date": "Enter the actual submission date, in DD-MM-YYYY.",
  "Submission Reference":
      "Enter the acknowledgement or receipt number from the authority.",
  "Payment Reference": "Enter the bank or payment receipt reference.",
  "Trigger Date":
      "Enter the event date used to determine this obligation's deadline.",
  "Override Reason":
      "Explain why the proposed value or date needs an exception.",
  "Document Name": "Enter a readable name for this supporting document.",
  "Original Filename":
      "Enter the source filename as received; preserve the original file.",
  "Extracted Date":
      "Review the transaction date proposed from the source document.",
  "Merchant / Supplier": "Enter the seller shown on the receipt or invoice.",
  "Match": "Choose whether this document matches an existing transaction.",
  "Existing Transaction":
      "Identify the existing transaction this document belongs to.",
  "Confirmed Filename":
      "Review the final filename to use when filing is connected.",
  "Destination Folder":
      "Specify the chosen root folder for this document's filing structure.",
  "Source Transaction": "Identify the transaction that owns this document.",
  "Version": "Enter the document revision identifier.",
  "Final Filename": "Review the filename recorded for the filed document.",
  "Destination": "Specify where the document or export should be stored.",
  "Conflict Action": "Choose how to resolve an existing filename without overwriting an original.",
  "Failure Details":
      "Describe what failed so the filing attempt can be reviewed.",
  "Review Type": "Choose the kind of accounting correction being proposed.",
  "Transaction Type": "Choose the transaction represented by this proposal.",
  "Reason": "Explain why this transaction or correction is needed.",
  "Debit Account": "Choose the account to debit in the proposed entry.",
  "Credit Account": "Choose the account to credit in the proposed entry.",
  "Decision": "Choose whether to approve, reject or return the proposal for correction.",
  "Reviewer Note": "Explain the review decision and any required follow-up.",
  "From Account": "Choose the bank or cash account the money leaves.",
  "To Account": "Choose the bank or cash account receiving the money.",
  "Comparison":
      "Choose the earlier period to display beside the current report.",
  "Columns": "Choose how report values should be grouped into columns.",
  "Show Zero Balances": "Include report rows whose balance is zero.",
  "Include Subaccounts":
      "Include the detailed accounts beneath each parent account.",
  "Code": "Enter a unique short code for this record.",
  "Tax Registration Number":
      "Enter the number issued for this tax registration.",
  "Transaction Reference":
      "Enter the reference that identifies the related transaction.",
  "Recurring":
      "Repeat this transaction on a schedule, with review before posting.",
  "Frequency":
      "Choose the regular repeat interval, or Custom for your own schedule.",
  "Every": "Enter a positive number for the interval, such as 2 for every two months.",
  "Interval Unit":
      "Choose whether the custom interval counts days, weeks, months or years.",
  "Start Date": "Enter the first scheduled date, in DD-MM-YYYY.",
  "End Condition": "Choose whether the schedule continues, ends on a date, or stops after a set count.",
  "End Date / Occurrence Count": "Enter the end date or number of occurrences matching the chosen end condition.",
  "Month-End Rule":
      "Choose how to schedule months that do not contain the original day.",
  "Quantity": "Enter the number of units supplied or purchased.",
  "Rate": "Enter the price per unit in the transaction currency.",
  "Account": "Choose the account that classifies this transaction line.",
  "Number Of Days":
      "Enter the number of days after issue before payment is due.",
  "Due Day Of Month": "Enter the calendar day on which payment is due.",
  "Cutoff Day":
      "Enter the issue-day cutoff for moving the due date into the next month.",
};
