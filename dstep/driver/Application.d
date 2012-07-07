/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Oct 1, 2011
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module dstep.driver.Application;

import std.getopt;
import std.stdio : writeln, stderr;

import DStack = dstack.application.Application;

import mambo.core._;
import mambo.util.Singleton;
import mambo.util.Use;

import clang.c.index;

import clang.Index;
import clang.TranslationUnit;

import dstep.core.Exceptions;
import dstep.translator.Translator;

class Application : DStack.Application
{
	mixin Singleton;
	
	enum Version = "0.0.1";
	
	private
	{
		string[] inputFiles;
		
		Index index;
		TranslationUnit translationUnit;
		DiagnosticVisitor diagnostics;
		
		string output = "foo.d";
		Language language;
		string[] argsToRestore;
		bool helpFlag;
	}
	
	override void run ()
	{
		handleArguments;

		if (!helpFlag)
			startConversion(inputFiles.first);
	}

private:
	
	void startConversion (string file)
	{
		index = Index(false, false);
		translationUnit = TranslationUnit.parse(index, file, args[1 .. $]);
		
		if (!translationUnit.isValid)
			throw new DStepException("An unknown error occurred");
		
		diagnostics = translationUnit.diagnostics;
		
		scope (exit)
			clean;
			
		if (handleDiagnostics)
		{
			Translator.Options options;
			options.outputFile = output;
			options.language = language;

			auto translator = new Translator(file, translationUnit, options);
			translator.translate;
		}
	}
	
	bool anyErrors ()
	{
		return diagnostics.length > 0;
	}
	
	void handleArguments ()
	{
		getopt(args,
			std.getopt.config.caseSensitive,
			std.getopt.config.passThrough,
			"o|output", &output,
			"x", &handleLanguage,
			"h|help", &help);

		if (helpFlag)
			return;

		if (args.any!(e => e == "-ObjC"))
			handleObjectiveC();

		collectInputFiles();
		restoreArguments(argsToRestore);
	}
	
	void handleObjectiveC ()
	{
		language = Language.objC;
		//args = remove(args, "-ObjC");
		argsToRestore ~= "-ObjC";
	}

	void handleLanguage (string option, string language)
	{
		switch (language)
		{
			case "c":
			case "c-header":
				this.language = Language.c;
			break;
		
			// Can't handle C++ yet
			//
			// case "c++":
			// case "c++-header":
			// 	this.language = Language.cpp;
			// break;
		
			case "objective-c":
			case "objective-c-header":
				this.language = Language.objC;
			break;

			default:
				throw new DStepException(`Unrecognized language "` ~ language ~ `"`);
		}

		argsToRestore ~= "-x";
		argsToRestore ~= language;
	}

	/**
	 * Restores the given arguments back into the list of argument passed to the application
	 * on the command line.
	 * 
	 * Use this method to restore arguments that were remove by std.getopt. This method is
	 * available since we want to handle some arguments ourself but also let Clang handle
	 * them.
	 */
	void restoreArguments (string[] args ...)
	{
		/*
		 * We're inserting the argument(s) at the beginning of the argument list to avoid
		 * being processed by std.getopt again, resulting in an infinite loop.
		 */
		this.args.insertInPlace(1, args);
	}

	void collectInputFiles ()
	{
		foreach (i, arg ; args[1 .. $])
			if (arg.first != '-' && args[i].first != '-')
                inputFiles ~= arg;

		if (inputFiles.isEmpty)
		{
			help();
			return;
		}

		args = args.remove(inputFiles);
	}
	
	bool handleDiagnostics ()
	{
	    bool translate = true;
	    	
		foreach (diag ; diagnostics)
		{
		    auto severity = diag.severity;
		    
		    with (CXDiagnosticSeverity)
		        if (translate)
	                translate = !(severity == CXDiagnostic_Error || severity == CXDiagnostic_Fatal);

	        writeln(stderr, diag.format);
		}

		return translate;
	}

	void help ()
	{
		helpFlag = true;

		println("Usage: dstep [options] <input>");
		println("Version: ", Version);
		println();
		println("Options:");
		println("    -o, --output <file>    Write output to <file>.");
		println("    -ObjC                  Treat source input file as Objective-C input.");
		println("    -x <language>          Treat subsequent input files as having type <language>.");
		println("    -h, --help             Show this message and exit.");
		println();
		println("All options that Clang accepts can be used as well.");
		println();
		println("Use the `-h' flag for help.");
	}

	void clean ()
	{
		translationUnit.dispose;
		index.dispose;
	}
}