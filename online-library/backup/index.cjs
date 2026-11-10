exports.main_handler=async(event,context)=>(await import('./backup/runtime.mjs')).main(event,context);
