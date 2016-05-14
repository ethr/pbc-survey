option errorabend;
ods noproctitle;

* Create output directory;
data _null_;
rc = dcreate("output", ".\");
file log;
put rc;
call symput("OUTPATH", rc);
run;

ods html body=".\output\output.html"
	gpath = ".\output\" (url=".");

filename dir '.';
%include dir(ARRAY);
%include dir(DO_OVER);
%include dir(NUMLIST);

option mprint;

%let CSV_LOCATION = C:\Users\Ethr\AppData\Local\Temp\responses.tsv;
%let CSV_LOCATION = C:\Users\Ethr\AppData\Local\Temp\response_dusty.csv;

proc import datafile="&CSV_LOCATION" out=inputRaw dbms=tab replace;
	guessingrows=32727;
    getnames=no;
    mixed=yes;
    datarow=2;
run;

%ARRAY(column_names, VALUES=
	timestamp/
	age/
	response/
	location/
	loneliness/
	health/
	relationships/
	family_matters/
	faith_matters/
	time_pressures/
	bereavement/
	age_issues/
	employment/
	financial/
	school/
	bullying/
	civil_liberties/
	politics/
	society/
	other/,
	DELIM=/);

%ARRAY(column_names2, VALUES=
	loneliness/
	health/
	relationships/
	family_matters/
	faith_matters/
	time_pressures/
	bereavement/
	age_issues/
	employment/
	financial/
	school/
	bullying/
	civil_liberties/
	politics/
	society/
	other/,
	DELIM=/);

data inputRaw;
set inputRaw;
 %DO_OVER(column_names,
	 PHRASE=label ?=?;)
 %DO_OVER(column_names,
	 PHRASE=?_char=input(var?_i_, $256.);)
 %DO_OVER(column_names2,
	 PHRASE=?=input(?_char, BEST.);)
 age = age_char;
 location = location_char;
 timestamp = timestamp_char;
 response = response_char;
 keep location age timestamp response;
 %DO_OVER(column_names2,
	 PHRASE=keep ?;)
run;

proc print data=inputRaw(obs=10);
title "Sample of the raw data";
run;

* Print bad data. Hopefully this can be fixed up;
proc print data=inputRaw;
title "Bad input data";
WHERE NOT (sum(%DO_OVER(column_names2,
 PHRASE=?,BETWEEN=COMMA)) = 1 AND
 age in ("u18", "18-29", "30-49", "50-64", "65+"));
run;

* Apply validation;
data inputRaw;
	set inputRaw;
	WHERE sum(%DO_OVER(column_names2,
	 PHRASE=?,BETWEEN=COMMA)) = 1 AND
	 age in ("u18", "18-29", "30-49", "50-64", "65+");
run;

proc print data=inputRaw(obs=10);
title "Sample of the data after validation";
run;

* Split responses into words and do some simple counting;
* Currently a bit tricky to filter out 'bad' words. Probably need a dictonary;
* of nouns to check against;
data input_split;
	set inputRaw;
	keep word;
	do i = 1 by 1;
		word = scan(response, i, ' -&.\/""''@?+,~#0123456789');
		word = lowcase(word);
		if missing(word) then leave;
		else output;
	end;
run;
proc freq data=input_split noprint order=freq;
table word / out=words_freq;
run;
proc print data=words_freq(obs=20) noobs;
title "Top 20 words in the responses";
where word not in ("of", "and", "a", "to", "the", "in", "the", "for", "more", "not",
	"they", "s", "one", "on", "lack", "too", "with", "other", "getting", "i", "when",
	"are", "me", "you", "bad", "no", "having", "t", "it");
run;

data input_for_freq(keep=category age location);
	set inputRaw;
	length category $ 32;
	label category = "Category";
	%DO_OVER(column_names2, PHRASE=if ? then category = "?";)
run;
proc freq data=input_for_freq;
title "Frequency counts for each response variable";
table age / nocum;
table category / nocum;
table location / nocum;
run;

* Summarise frequency of response by age group and location;
proc sort data=input_for_freq;
by location;
run;
proc freq data=input_for_freq;
title "Age v. Category by location";
table  age * category / nocum nopercent norow;
by location;
run;

proc freq data=input_for_freq;
title "Age v. Category across all locations";
table age * category   / nocum nocol nopercent;
run;

proc gchart data=input_for_freq;
title "Responses from all age groups";
pie age;
run;

proc gchart data=input_for_freq;
title "Responses in each category"; 
pie category;
run;

proc sort data=input_for_freq;
by age;
run;
proc gchart data=input_for_freq;
title "Responses in each category by age"; 
pie category;
by age;
run;

goptions xpixels=1024 ypixels=768;
proc gchart data=input_for_freq;
pattern1 color=grayCC;
axis2 label=("Category");
title "Responses in each category by age"; 
vbar category / width=15 type=pct inside=freq outside=pct maxis=axis2;
run;

/**
 * Calculate correlations
**/

data input_for_corr;
	set inputRaw;
	drop age timestamp response location;
	under18 = 0;
	between18_and_29 = 0;
	between30_and_49 = 0;
	between50_and_64 = 0;
	over65 = 0;
	 %DO_OVER(column_names2,
	 PHRASE=if missing(?) then ? = 0.0;)
	if age = "u18" then under18 = 1;
	else if age = "18-29" then between18_and_29 = 1;
	else if age = "30-49" then between30_and_49 = 1;
	else if age = "50-64" then between50_and_64 = 1;
	else if age = "65+" then over65 = 1;
	else error "Not a valid age group"; 
run;

ods select measures;
ods html exclude all;
proc freq data = input_for_corr;
  tables
	  (under18 between18_and_29 between30_and_49 over65) *
	  (%DO_OVER(column_names2, PHRASE=?))
	  / plcorr out=bar;
	ods output measures=stats (where=(statistic="Tetrachoric Correlation"
                                     or statistic="Polychoric Correlation")
                              keep = statistic table value);
run;
ods html exclude none;
data stats;
  set stats;
  group = floor((_n_ - 1)/3);
  age_group = scan(table, 2, " *");
  category = scan(table, 3, " *");
  if age_group = "under18" then age_group = "Under 18";
	if age_group = "between18_and_29" then age_group = "Between 18 and 29";
	if age_group = "between30_and_49" then age_group = "Between 30 and 49";
	if age_group = "between50_and_64" then age_group = "Between 50 and 64";
	if age_group = "over65" then age_group = "65+";
  keep value age_group category;
run;
proc sort data=stats;
by age_group descending value;
run;
proc print data = stats noobs;
title "Correlations with category for #byval(age_group)";
by age_group;
run;

ods html close;
